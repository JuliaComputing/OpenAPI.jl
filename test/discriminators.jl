@testset "discriminators and generated-name collisions" begin
    @testset "explicit and default discriminator mappings" begin
        document = minimal_openapi(
            "3.2.0",
            OpenAPI.obj(
                "/pets" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "getPet",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/Pet",
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
                "Cat" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["kind", "meows"],
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj(
                            "type" => "string",
                            "enum" => ["cat", "feline", "Cat"],
                        ),
                        "meows" => OpenAPI.obj("type" => "boolean"),
                    ),
                    "additionalProperties" => false,
                ),
                "Dog" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["kind", "barks"],
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj(
                            "type" => "string",
                            "enum" => ["dog", "canine", "Dog"],
                        ),
                        "barks" => OpenAPI.obj("type" => "boolean"),
                    ),
                    "additionalProperties" => false,
                ),
                "OtherPet" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["kind", "note"],
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj("type" => "string"),
                        "note" => OpenAPI.obj("type" => "string"),
                    ),
                    "additionalProperties" => false,
                ),
                "Pet" => OpenAPI.obj(
                    "oneOf" => Any[
                        OpenAPI.obj("\$ref" => "#/components/schemas/Cat"),
                        OpenAPI.obj("\$ref" => "#/components/schemas/Dog"),
                        OpenAPI.obj("\$ref" => "#/components/schemas/OtherPet"),
                    ],
                    "discriminator" => OpenAPI.obj(
                        "propertyName" => "kind",
                        "mapping" => OpenAPI.obj(
                            "feline" => "#/components/schemas/Cat",
                            "canine" => "#/components/schemas/Dog",
                        ),
                        "defaultMapping" => "#/components/schemas/OtherPet",
                    ),
                ),
            ),
        )

        source = OpenAPI.client(document; name = "DiscriminatorClient")
        host = Module(:DiscriminatorClientHost)
        Base.include_string(host, source, "DiscriminatorClient.jl")
        client_module = Base.invokelatest(getfield, host, :DiscriminatorClient)
        response_media = only(only(client_module._OP_getpet.responses).media)

        decode_pet(json) = Base.invokelatest(
            OpenAPI.Runtime._decode_body,
            client_module.DEFAULT_CLIENT,
            client_module.Pet,
            "application/json",
            Vector{UInt8}(codeunits(json)),
            response_media.schema,
        )
        cat = decode_pet("{\"kind\":\"feline\",\"meows\":true}")
        dog = decode_pet("{\"kind\":\"canine\",\"barks\":true}")
        other = decode_pet("{\"kind\":\"iguana\",\"note\":\"quiet\"}")
        implicit_cat = decode_pet("{\"kind\":\"Cat\",\"meows\":true}")
        implicit_dog = decode_pet("{\"kind\":\"Dog\",\"barks\":true}")
        @test cat.value isa client_module.Cat
        @test cat.value.meows
        @test dog.value isa client_module.Dog
        @test dog.value.barks
        @test other.value isa client_module.OtherPet
        @test other.value.note == "quiet"
        @test implicit_cat.value isa client_module.Cat
        @test implicit_dog.value isa client_module.Dog

        bad = deepcopy(document)
        bad["components"]["schemas"]["Pet"]["discriminator"]["mapping"]["bad"] =
            "#/components/schemas/Missing"
        error = @test_throws OpenAPI.OpenAPIError OpenAPI.plan(bad)
        @test :invalid_discriminator_mapping in
              Set(diagnostic.code for diagnostic in error.value.diagnostics)
    end

    @testset "implicit mappings and collision-safe Julia names" begin
        document = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/value/{client}" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "module",
                        "parameters" => Any[
                            OpenAPI.obj(
                                "name" => "client",
                                "in" => "path",
                                "required" => true,
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                            OpenAPI.obj(
                                "name" => "foo-bar",
                                "in" => "query",
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                            OpenAPI.obj(
                                "name" => "foo_bar",
                                "in" => "query",
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ],
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "value",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/ImplicitPet",
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
                "Cat" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["kind", "foo-bar", "foo_bar"],
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj("const" => "Cat"),
                        "foo-bar" => OpenAPI.obj("type" => "string"),
                        "foo_bar" => OpenAPI.obj("type" => "integer"),
                    ),
                    "additionalProperties" => false,
                ),
                "Dog" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["kind"],
                    "properties" => OpenAPI.obj(
                        "kind" => OpenAPI.obj("const" => "Dog"),
                    ),
                    "additionalProperties" => false,
                ),
                "ImplicitPet" => OpenAPI.obj(
                    "oneOf" => Any[
                        OpenAPI.obj("\$ref" => "#/components/schemas/Cat"),
                        OpenAPI.obj("\$ref" => "#/components/schemas/Dog"),
                    ],
                    "discriminator" => OpenAPI.obj("propertyName" => "kind"),
                ),
            ),
        )

        plan = OpenAPI.plan(document; name = "CollisionClient")
        operation = only(plan.operations)
        @test operation.name == "module_"
        @test [parameter.name for parameter in operation.parameters] ==
              ["client_2", "foo_bar", "foo_bar_2"]
        cat_plan = only(model for model in plan.models if model.name == "Cat")
        @test [field.name for field in cat_plan.fields] ==
              ["kind", "foo_bar", "foo_bar_2"]
        @test [field.wire_name for field in cat_plan.fields] ==
              ["kind", "foo-bar", "foo_bar"]

        source = OpenAPI.client(plan)
        host = Module(:CollisionClientHost)
        Base.include_string(host, source, "CollisionClient.jl")
        client_module = Base.invokelatest(getfield, host, :CollisionClient)
        pet = Base.invokelatest(
            client_module._decode,
            client_module.ImplicitPet,
            Dict("kind" => "Cat", "foo-bar" => "x", "foo_bar" => 7),
        )
        @test pet.value isa client_module.Cat
        @test pet.value.foo_bar == "x"
        @test pet.value.foo_bar_2 == 7
    end

    @testset "document text and generated locals cannot alter source" begin
        field_names = [
            "raw",
            "value",
            "unknown",
            "key",
            "item",
            "output",
            "haskey",
            "keys",
            "collect",
            "setdiff",
            "isempty",
            "join",
        ]
        summary = "literal \$(expression) and triple quote \"\"\"\nconst INJECTED_DOC = true"
        document = OpenAPI.obj(
            "openapi" => "3.1.1",
            "info" => OpenAPI.obj(
                "title" => "Quoted metadata",
                "version" => "1.0\nconst INJECTED_VERSION = true",
            ),
            "paths" => OpenAPI.obj(
                "/hostile" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "length",
                        "summary" => summary,
                        "parameters" => Any[
                            OpenAPI.obj(
                                "name" => "values",
                                "in" => "query",
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                            OpenAPI.obj(
                                "name" => "stream_to",
                                "in" => "query",
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ],
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "hostile fields",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/Hostile",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
            "components" => OpenAPI.obj(
                "schemas" => OpenAPI.obj(
                    "Hostile" => OpenAPI.obj(
                        "type" => "object",
                        "required" => field_names,
                        "properties" => OpenAPI.obj(
                            (name => OpenAPI.obj("type" => "string") for name in field_names)...,
                        ),
                        "additionalProperties" => false,
                    ),
                ),
            ),
        )

        plan = OpenAPI.plan(document; name = "HostileClient")
        operation = only(plan.operations)
        @test operation.name == "length_"
        @test [parameter.name for parameter in operation.parameters] ==
              ["values", "stream_to_2"]
        source = OpenAPI.client(plan)
        @test occursin("version \"1.0\\nconst INJECTED_VERSION = true\"", source)
        host = Module(:HostileClientHost)
        Base.include_string(host, source, "HostileClient.jl")
        @test !isdefined(host, :INJECTED_VERSION)
        client_module = Base.invokelatest(getfield, host, :HostileClient)
        @test !isdefined(client_module, :INJECTED_DOC)
        binding = Base.Docs.Binding(client_module, :length_)
        doc = Base.Docs.docstr(binding, Tuple{})
        @test occursin(summary, String(only(doc.text)))

        raw = Dict(name => name for name in field_names)
        value = Base.invokelatest(client_module._decode, client_module.Hostile, raw)
        @test all(name -> getproperty(value, Symbol(name)) == name, field_names)
        @test Base.invokelatest(client_module._encode, value) == raw

        server_source = OpenAPI.server(document; name = "HostileServer")
        server_host = Module(:HostileServerHost)
        Base.include_string(server_host, server_source, "HostileServer.jl")
        @test !isdefined(server_host, :INJECTED_VERSION)
    end

    @testset "forward recursive union declarations" begin
        document = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/errors" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "errors",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "errors",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/ErrorDetails",
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
                "ErrorDetails" => OpenAPI.obj(
                    "oneOf" => Any[
                        OpenAPI.obj(
                            "type" => "object",
                            "additionalProperties" => OpenAPI.obj(
                                "\$ref" => "#/components/schemas/ErrorDetails",
                            ),
                        ),
                        OpenAPI.obj("type" => "string"),
                    ],
                ),
            ),
        )
        source = OpenAPI.client(document; name = "RecursiveUnionClient")
        host = Module(:RecursiveUnionClientHost)
        Base.include_string(host, source, "RecursiveUnionClient.jl")
        client_module = Base.invokelatest(
            getfield,
            host,
            :RecursiveUnionClient,
        )
        value = Base.invokelatest(
            client_module._decode,
            client_module.ErrorDetails,
            Dict("nested" => "leaf"),
        )
        @test value.value isa client_module.ErrorDetails1
        @test value.value.additional_properties["nested"] isa
              client_module.ErrorDetails
        @test value.value.additional_properties["nested"].value == "leaf"
    end
end
