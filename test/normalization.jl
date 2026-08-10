function minimal_openapi(version::AbstractString, paths)
    return OpenAPI.obj(
        "openapi" => String(version),
        "info" => OpenAPI.obj("title" => "Test", "version" => "1.0.0"),
        "paths" => paths,
    )
end

@testset "OpenAPI normalization and schema compatibility" begin
    @testset "source locations and duplicate keys" begin
        json = """{
          "openapi": "3.1.0",
          "info": {"title": "Test", "version": "1"},
          "paths": {}
        }"""
        loaded = OpenAPI.load(json)
        openapi_location = OpenAPI.location(
            loaded,
            OpenAPI.Resources.JSONPointer("/openapi"),
        )
        @test openapi_location.position == OpenAPI.SourcePosition(2, 3, 5)

        yaml = """openapi: 3.1.0
        info:
          title: Test
          version: "1"
        paths: {}
        """
        loaded_yaml = OpenAPI.load(yaml)
        title_location = OpenAPI.location(
            loaded_yaml,
            OpenAPI.Resources.JSONPointer("/info/title"),
        )
        @test title_location.position.line == 3
        @test title_location.position.column == 3

        duplicate = """{
          "openapi": "3.1.0",
          "info": {"title": "Test", "title": "Other", "version": "1"},
          "paths": {}
        }"""
        diagnostics = OpenAPI.check(duplicate)
        @test length(diagnostics) == 1
        @test only(diagnostics).code === :parse_error
        @test only(diagnostics).location.position.line == 3
        @test occursin("duplicate JSON object key", only(diagnostics).message)

        invalid = replace(json, "\"title\": \"Test\"" => "\"description\": \"Test\"")
        issue = only(filter(diagnostic -> diagnostic.code === :spec_schema, OpenAPI.check(invalid)))
        @test issue.location.position !== nothing
        @test issue.location.position.line == 3
    end

    @testset "OAS 3.0 nullable schemas compile as nullable JSON Schema" begin
        document = minimal_openapi(
            "3.0.3",
            OpenAPI.obj(
                "/nullable" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "getNullable",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "nullable value",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "type" => "string",
                                            "nullable" => true,
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        source = OpenAPI.client(document; name = "NullableClient")
        host = Module(:NullableClientHost)
        Base.include_string(host, source, "NullableClient.jl")
        client_module = Base.invokelatest(getfield, host, :NullableClient)
        response = only(client_module._OP_getnullable.responses)
        media = only(response.media)
        @test Base.invokelatest(client_module._schema_valid, client_module._SPEC, media[3], nothing)
        @test Base.invokelatest(
            OpenAPI.Runtime._decode_body,
            client_module.DEFAULT_CLIENT,
            Union{Nothing,String},
            "application/json",
            Vector{UInt8}(codeunits("null")),
            media[3],
        ) === nothing

        constrained = minimal_openapi(
            "3.0.3",
            OpenAPI.obj(
                "/direct" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "direct",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "direct nullable",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/DirectNullable",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
                "/constrained" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "constrained",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "enum excludes null",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/Constrained",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
                "/composed" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "composed",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "nullable has no direct type",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/Composed",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
                "/instance" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "instance",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "object enum instance",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/InstanceEnum",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
                "/choice" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "choice",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "nullable wraps oneOf",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/PermissiveChoice",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        constrained["components"] = OpenAPI.obj(
            "schemas" => OpenAPI.obj(
                "BaseString" => OpenAPI.obj("type" => "string"),
                "DirectNullable" => OpenAPI.obj(
                    "type" => "string",
                    "nullable" => true,
                ),
                "Constrained" => OpenAPI.obj(
                    "type" => "string",
                    "nullable" => true,
                    "enum" => ["present"],
                ),
                "Composed" => OpenAPI.obj(
                    "nullable" => true,
                    "allOf" => Any[
                        OpenAPI.obj("\$ref" => "#/components/schemas/BaseString"),
                    ],
                ),
                "PermissiveChoice" => OpenAPI.obj(
                    "nullable" => true,
                    "oneOf" => Any[
                        OpenAPI.obj("\$ref" => "#/components/schemas/BaseString"),
                        OpenAPI.obj("type" => "integer"),
                    ],
                ),
                "InstanceEnum" => OpenAPI.obj(
                    "type" => "object",
                    "nullable" => true,
                    "enum" => Any[
                        OpenAPI.obj("type" => "string", "nullable" => true),
                    ],
                ),
            ),
        )
        constrained_source = OpenAPI.client(constrained; name = "NullableRulesClient")
        @test constrained_source ==
              OpenAPI.client(constrained; name = "NullableRulesClient")
        constrained_host = Module(:NullableRulesClientHost)
        Base.include_string(
            constrained_host,
            constrained_source,
            "NullableRulesClient.jl",
        )
        rules = Base.invokelatest(getfield, constrained_host, :NullableRulesClient)
        descriptor(name) = only(only(getfield(rules, Symbol("_OP_", name)).responses).media)[3]
        @test Base.invokelatest(rules._schema_valid, rules._SPEC, descriptor("direct"), nothing)
        @test !Base.invokelatest(
            rules._schema_valid, rules._SPEC,
            descriptor("constrained"),
            nothing,
        )
        @test !Base.invokelatest(rules._schema_valid, rules._SPEC, descriptor("composed"), nothing)
        instance = Dict("type" => "string", "nullable" => true)
        @test Base.invokelatest(rules._schema_valid, rules._SPEC, descriptor("instance"), instance)
        @test Nothing <: rules.DirectNullable
        @test !(Nothing <: rules.Constrained)
        @test !(Nothing <: rules.Composed)

        permissive_api = OpenAPI.normalize(constrained; strict = false)
        @test :legacy_nullable_without_type in
              Set(diagnostic.code for diagnostic in permissive_api.diagnostics)
        permissive_source = OpenAPI.client(
            permissive_api;
            name = "PermissiveNullableClient",
        )
        permissive_host = Module(:PermissiveNullableClientHost)
        Base.include_string(
            permissive_host,
            permissive_source,
            "PermissiveNullableClient.jl",
        )
        permissive = Base.invokelatest(
            getfield,
            permissive_host,
            :PermissiveNullableClient,
        )
        composed_descriptor = only(
            only(permissive._OP_composed.responses).media,
        )[3]
        @test Base.invokelatest(
            permissive._schema_valid, permissive._SPEC,
            composed_descriptor,
            nothing,
        )
        constrained_descriptor = only(
            only(permissive._OP_constrained.responses).media,
        )[3]
        @test !Base.invokelatest(
            permissive._schema_valid, permissive._SPEC,
            constrained_descriptor,
            nothing,
        )
        @test Nothing <: fieldtype(permissive.Composed, :value)
        @test !(Nothing <: fieldtype(permissive.Constrained, :value))
        @test Base.invokelatest(
            permissive._decode,
            permissive.Composed,
            nothing,
        ).value === nothing
        choice_descriptor = only(only(permissive._OP_choice.responses).media)[3]
        @test Base.invokelatest(
            permissive._schema_valid, permissive._SPEC,
            choice_descriptor,
            nothing,
        )
        @test Nothing <: fieldtype(permissive.PermissiveChoice, :value)
        @test Base.invokelatest(
            permissive._decode,
            permissive.PermissiveChoice,
            nothing,
        ).value === nothing
    end

    @testset "modern schema planning" begin
        document = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/directional" => OpenAPI.obj(
                    "post" => OpenAPI.obj(
                        "operationId" => "roundTrip",
                        "requestBody" => OpenAPI.obj(
                            "required" => true,
                            "content" => OpenAPI.obj(
                                "application/json" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj(
                                        "\$ref" => "#/components/schemas/Directional",
                                    ),
                                ),
                            ),
                        ),
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "directional value",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/Directional",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        document["components"] = OpenAPI.obj(
            "schemas" => OpenAPI.obj(
                "RootModel" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["base"],
                    "properties" => OpenAPI.obj(
                        "base" => OpenAPI.obj("type" => "string"),
                    ),
                    "additionalProperties" => false,
                ),
                "Extended" => OpenAPI.obj(
                    "\$ref" => "#/components/schemas/RootModel",
                    "type" => "object",
                    "required" => ["count"],
                    "properties" => OpenAPI.obj(
                        "count" => OpenAPI.obj("type" => "integer"),
                    ),
                ),
                "PatternMap" => OpenAPI.obj(
                    "type" => "object",
                    "patternProperties" => OpenAPI.obj(
                        "^x-" => OpenAPI.obj("type" => "integer"),
                    ),
                    "additionalProperties" => false,
                ),
                "VariableTuple" => OpenAPI.obj(
                    "type" => "array",
                    "prefixItems" => Any[
                        OpenAPI.obj("type" => "string"),
                        OpenAPI.obj("type" => "integer"),
                    ],
                    "items" => false,
                ),
                "ExactTuple" => OpenAPI.obj(
                    "type" => "array",
                    "prefixItems" => Any[
                        OpenAPI.obj("type" => "string"),
                        OpenAPI.obj("type" => "integer"),
                    ],
                    "items" => false,
                    "minItems" => 2,
                ),
                "RecursiveList" => OpenAPI.obj(
                    "type" => "array",
                    "items" => OpenAPI.obj(
                        "\$ref" => "#/components/schemas/RecursiveList",
                    ),
                ),
                "ChoiceA" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["kind", "input_secret", "output_id"],
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj("const" => "a"),
                        "input_secret" => OpenAPI.obj(
                            "type" => "string",
                            "writeOnly" => true,
                        ),
                        "output_id" => OpenAPI.obj(
                            "type" => "integer",
                            "readOnly" => true,
                        ),
                    ),
                    "additionalProperties" => false,
                ),
                "ChoiceB" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["kind", "input_secret", "output_id"],
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj("const" => "b"),
                        "input_secret" => OpenAPI.obj(
                            "type" => "string",
                            "writeOnly" => true,
                        ),
                        "output_id" => OpenAPI.obj(
                            "type" => "integer",
                            "readOnly" => true,
                        ),
                    ),
                    "additionalProperties" => false,
                ),
                "DirectionalChoice" => OpenAPI.obj(
                    "oneOf" => Any[
                        OpenAPI.obj("\$ref" => "#/components/schemas/ChoiceA"),
                        OpenAPI.obj("\$ref" => "#/components/schemas/ChoiceB"),
                    ],
                ),
                "Directional" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["id", "secret", "name", "choice"],
                    "properties" => OpenAPI.obj(
                        "id" => OpenAPI.obj(
                            "type" => "integer",
                            "readOnly" => true,
                        ),
                        "secret" => OpenAPI.obj(
                            "type" => "string",
                            "writeOnly" => true,
                        ),
                        "name" => OpenAPI.obj("type" => "string"),
                        "choice" => OpenAPI.obj(
                            "\$ref" => "#/components/schemas/DirectionalChoice",
                        ),
                    ),
                    "additionalProperties" => false,
                ),
            ),
        )
        source = OpenAPI.client(document; name = "ModernSchemaClient")
        host = Module(:ModernSchemaClientHost)
        Base.include_string(host, source, "ModernSchemaClient.jl")
        client_module = Base.invokelatest(getfield, host, :ModernSchemaClient)

        @test fieldnames(client_module.Extended) == (:base, :count)
        @test fieldtype(client_module.Extended, :base) === String
        @test fieldtype(client_module.Extended, :count) === Int64
        @test fieldnames(client_module.PatternMap) == (:additional_properties,)
        @test fieldtype(client_module.PatternMap, :additional_properties) ===
              Dict{String,Int64}
        @test client_module.VariableTuple === Vector{Union{Int64,String}}
        @test client_module.ExactTuple === Tuple{String,Int64}
        @test fieldtype(client_module.RecursiveList, :value) ===
              Vector{client_module.RecursiveList}
        recursive = Base.invokelatest(
            client_module._decode,
            client_module.RecursiveList,
            Any[Any[]],
        )
        @test recursive.value[1] isa client_module.RecursiveList
        @test isempty(recursive.value[1].value)

        @test fieldnames(client_module.DirectionalInput) == (:secret, :name, :choice)
        @test fieldnames(client_module.DirectionalOutput) == (:id, :name, :choice)
        input_choice = Base.invokelatest(
            client_module.DirectionalChoiceInput,
            Base.invokelatest(
                client_module.ChoiceAInput;
                kind = "a",
                input_secret = "choice-token",
            ),
        )
        input = Base.invokelatest(
            client_module.DirectionalInput;
            secret = "token",
            name = "Ada",
            choice = input_choice,
        )
        encoded = Base.invokelatest(client_module._encode, input)
        @test encoded == Dict(
            "secret" => "token",
            "name" => "Ada",
            "choice" => Dict(
                "kind" => "a",
                "input_secret" => "choice-token",
            ),
        )
        response_media = only(only(client_module._OP_roundtrip.responses).media)
        output = Base.invokelatest(
            OpenAPI.Runtime._decode_body,
            client_module.DEFAULT_CLIENT,
            client_module.DirectionalOutput,
            "application/json",
            Vector{UInt8}(
                codeunits(
                    "{\"id\":7,\"name\":\"Ada\",\"choice\":{\"kind\":\"a\",\"output_id\":9}}",
                ),
            ),
            response_media[3],
        )
        @test output.id == 7
        @test output.name == "Ada"
        @test output.choice.value isa client_module.ChoiceAOutput
        @test output.choice.value.output_id == 9
    end
end
