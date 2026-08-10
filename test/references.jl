@testset "OpenAPI reference resolution" begin
    @testset "relative files and cross-file schemas" begin
        directory = mktempdir()
        common = OpenAPI.obj(
            "\$defs" => OpenAPI.obj(
                "User" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["id", "name"],
                    "properties" => OpenAPI.obj(
                        "id" => OpenAPI.obj("type" => "integer"),
                        "name" => OpenAPI.obj("type" => "string"),
                    ),
                    "additionalProperties" => false,
                ),
            ),
            "parameters" => OpenAPI.obj(
                "Trace" => OpenAPI.obj(
                    "name" => "X-Trace",
                    "in" => "header",
                    "required" => false,
                    "schema" => OpenAPI.obj("type" => "string"),
                ),
            ),
        )
        common_path = joinpath(directory, "common.json")
        write(common_path, JSON.json(common))
        root_path = joinpath(directory, "openapi.yaml")
        write(
            root_path,
            """
            openapi: 3.1.1
            info:
              title: External
              version: "1"
            paths:
              /users/{id}:
                get:
                  operationId: getUser
                  parameters:
                    - name: id
                      in: path
                      required: true
                      schema:
                        type: integer
                    - \$ref: "./common.json#/parameters/Trace"
                  responses:
                    "200":
                      description: user
                      content:
                        application/json:
                          schema:
                            \$ref: "./common.json#/\$defs/User"
            components:
              schemas:
                User:
                  \$ref: "./common.json#/\$defs/User"
            """,
        )

        api = OpenAPI.normalize(root_path)
        @test length(api.operations) == 1
        operation = only(api.operations)
        @test operation.parameters[2].name == "X-Trace"
        @test operation.parameters[2].required === false
        @test length(api.registry) == 2

        source = OpenAPI.client(api; name = "ExternalClient")
        host = Module(:ExternalClientHost)
        Base.include_string(host, source, "ExternalClient.jl")
        C = Base.invokelatest(getfield, host, :ExternalClient)
        @test fieldnames(C.User) == (:id, :name)
        @test fieldtype(C.User, :id) === Int64
        @test fieldtype(C.User, :name) === String

        @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(
            root_path;
            max_resources = 1,
        )
    end

    @testset "OAS 3.0 nullable schemas in external component wrappers" begin
        directory = mktempdir()
        write(
            joinpath(directory, "common.yaml"),
            """
            components:
              schemas:
                Name:
                  type: string
                  nullable: true
                LegacyChoice:
                  nullable: true
                  oneOf:
                    - type: integer
                    - type: string
            """,
        )
        root = minimal_openapi(
            "3.0.3",
            OpenAPI.obj(
                "/name" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "getExternalName",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "name",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "./common.yaml#/components/schemas/Name",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
                "/legacy" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "getExternalLegacy",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "legacy choice",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "./common.yaml#/components/schemas/LegacyChoice",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        root_path = joinpath(directory, "openapi.json")
        write(root_path, JSON.json(root))

        strict_source = OpenAPI.client(root_path; name = "ExternalNullableStrict")
        strict_host = Module(:ExternalNullableStrictHost)
        Base.include_string(strict_host, strict_source, "ExternalNullableStrict.jl")
        Strict = Base.invokelatest(getfield, strict_host, :ExternalNullableStrict)
        name_media = only(only(Strict._OP_getexternalname.responses).media)
        legacy_media = only(only(Strict._OP_getexternallegacy.responses).media)
        @test name_media[2] == Union{Nothing,String}
        @test Base.invokelatest(Strict._schema_valid, Strict._SPEC, name_media[3], nothing)
        @test !Base.invokelatest(Strict._schema_valid, Strict._SPEC, legacy_media[3], nothing)

        permissive = OpenAPI.normalize(root_path; strict = false)
        @test any(
            diagnostic -> diagnostic.code === :legacy_nullable_without_type,
            permissive.diagnostics,
        )
        permissive_source = OpenAPI.client(
            permissive;
            name = "ExternalNullablePermissive",
        )
        permissive_host = Module(:ExternalNullablePermissiveHost)
        Base.include_string(
            permissive_host,
            permissive_source,
            "ExternalNullablePermissive.jl",
        )
        Permissive = Base.invokelatest(
            getfield,
            permissive_host,
            :ExternalNullablePermissive,
        )
        permissive_media = only(
            only(Permissive._OP_getexternallegacy.responses).media,
        )
        @test Nothing <: permissive_media[2]
        @test Base.invokelatest(
            Permissive._schema_valid, Permissive._SPEC,
            permissive_media[3],
            nothing,
        )
    end

    @testset "file sandbox" begin
        parent = mktempdir()
        source_directory = joinpath(parent, "source")
        mkdir(source_directory)
        external_path = joinpath(parent, "outside.json")
        write(
            external_path,
            JSON.json(
                OpenAPI.obj(
                    "type" => "object",
                    "properties" => OpenAPI.obj(
                        "value" => OpenAPI.obj("type" => "string"),
                    ),
                ),
            ),
        )
        root = OpenAPI.obj(
            "openapi" => "3.1.1",
            "info" => OpenAPI.obj("title" => "Sandbox", "version" => "1"),
            "paths" => OpenAPI.obj(
                "/x" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "getX",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "value",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "../outside.json",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        root_path = joinpath(source_directory, "openapi.json")
        write(root_path, JSON.json(root))
        @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(root_path)
        @test OpenAPI.normalize(root_path; file_roots = [parent]) isa
              OpenAPI.NormalizedAPI
    end

    @testset "portable generated schema identity" begin
        document = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/value" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "getValue",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "value",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "./common.yaml#/\$defs/Value",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        common = OpenAPI.obj(
            "\$defs" => OpenAPI.obj(
                "Value" => OpenAPI.obj(
                    "type" => "object",
                    "required" => ["id"],
                    "properties" => OpenAPI.obj(
                        "id" => OpenAPI.obj("type" => "integer"),
                    ),
                    "additionalProperties" => false,
                ),
            ),
        )
        directories = [mktempdir(), mktempdir()]
        sources = String[]
        for directory in directories
            # JSON is valid YAML. The .yaml suffix forces the schema retriever
            # through its YAML-to-JSON adapter without adding fixture noise.
            write(joinpath(directory, "common.yaml"), JSON.json(common))
            path = joinpath(directory, "openapi.json")
            write(path, JSON.json(document))
            push!(sources, OpenAPI.client(path; name = "PortableClient"))
        end
        @test sources[1] == sources[2]
        @test all(directory -> !occursin(directory, sources[1]), directories)

        portable_document = deepcopy(document)
        portable_document["paths"]["/value"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]["\$ref"] =
            "https://example.com/common.json#/\$defs/Value"
        encoded = JSON.json(portable_document)
        credentialed = OpenAPI.client(
            encoded;
            name = "PortableClient",
            base_uri = "https://user:pass@example.com/openapi.json?token=secret",
            allow_remote_refs = true,
            retriever = OpenAPI.Resources.MemoryRetriever(
                Dict(
                    OpenAPI.Resources.ResourceId("https://example.com/common.json") =>
                        JSON.json(common),
                ),
            ),
        )
        clean = OpenAPI.client(
            encoded;
            name = "PortableClient",
            base_uri = "https://example.com/openapi.json",
            allow_remote_refs = true,
            retriever = OpenAPI.Resources.MemoryRetriever(
                Dict(
                    OpenAPI.Resources.ResourceId("https://example.com/common.json") =>
                        JSON.json(common),
                ),
            ),
        )
        @test credentialed == clean
        @test !occursin("user:pass", credentialed)
        @test !occursin("token=secret", credentialed)
    end

    @testset "HTTP origin policy and redirects" begin
        external_schema = JSON.json(
            OpenAPI.obj(
                "\$defs" => OpenAPI.obj(
                    "User" => OpenAPI.obj(
                        "type" => "object",
                        "required" => ["id"],
                        "properties" => OpenAPI.obj(
                            "id" => OpenAPI.obj("type" => "integer"),
                        ),
                        "additionalProperties" => false,
                    ),
                ),
            ),
        )
        referenced_document(reference) = JSON.json(
            OpenAPI.obj(
                "openapi" => "3.1.1",
                "info" => OpenAPI.obj(
                    "title" => "HTTP references",
                    "version" => "1",
                ),
                "paths" => OpenAPI.obj(
                    "/users" => OpenAPI.obj(
                        "get" => OpenAPI.obj(
                            "operationId" => "getUsers",
                            "responses" => OpenAPI.obj(
                                "200" => OpenAPI.obj(
                                    "description" => "users",
                                    "content" => OpenAPI.obj(
                                        "application/json" => OpenAPI.obj(
                                            "schema" => OpenAPI.obj(
                                                "type" => "array",
                                                "items" => OpenAPI.obj(
                                                    "\$ref" => reference,
                                                ),
                                            ),
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )

        cross_schema_requests = Ref(0)
        same_schema_requests = Ref(0)
        cross_server = HTTP.serve!(
            function (request)
                if String(request.target) == "/schema.json"
                    cross_schema_requests[] += 1
                    return HTTP.Response(
                        200,
                        ["Content-Type" => "application/schema+json"],
                        external_schema,
                    )
                end
                return HTTP.Response(404)
            end,
            "127.0.0.1",
            0;
            verbose = false,
        )
        same_base = Ref("")
        cross_base = "http://127.0.0.1:$(HTTP.port(cross_server))"
        same_server = HTTP.serve!(
            function (request)
                target = String(request.target)
                if target == "/schema.json"
                    same_schema_requests[] += 1
                    return HTTP.Response(
                        200,
                        ["Content-Type" => "application/schema+json"],
                        external_schema,
                    )
                end
                target == "/same.json" && return HTTP.Response(
                    200,
                    ["Content-Type" => "application/openapi+json"],
                    referenced_document("/schema.json#/\$defs/User"),
                )
                target == "/cross.json" && return HTTP.Response(
                    200,
                    ["Content-Type" => "application/openapi+json"],
                    referenced_document(
                        cross_base * "/schema.json#/\$defs/User",
                    ),
                )
                target == "/redirect.json" && return HTTP.Response(
                    302,
                    ["Location" => same_base[] * "/same.json"],
                )
                target == "/oversized.json" && return HTTP.Response(
                    200,
                    ["Content-Type" => "application/openapi+json"],
                    repeat("x", 4096),
                )
                return HTTP.Response(404)
            end,
            "127.0.0.1",
            0;
            verbose = false,
        )
        same_base[] = "http://127.0.0.1:$(HTTP.port(same_server))"
        try
            same = OpenAPI.normalize(same_base[] * "/same.json")
            same_plan = OpenAPI.plan(same)
            @test same_schema_requests[] > 0
            @test startswith(only(same_plan.operations).return_type, "Vector{")
            @test any(
                field -> field.wire_name == "id" && field.type == "Int64",
                only(same_plan.models).fields,
            )

            blocked = @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(
                same_base[] * "/cross.json",
            )
            @test any(
                diagnostic -> diagnostic.code === :invalid_schema,
                blocked.value.diagnostics,
            )
            @test cross_schema_requests[] == 0
            allowed = OpenAPI.normalize(
                same_base[] * "/cross.json";
                allow_remote_refs = true,
            )
            @test cross_schema_requests[] > 0
            @test startswith(
                only(OpenAPI.plan(allowed).operations).return_type,
                "Vector{",
            )

            @test_throws OpenAPI.Resources.RetrievalError OpenAPI.load(
                same_base[] * "/redirect.json",
            )
            oversized = @test_throws OpenAPI.Resources.RetrievalError OpenAPI.load(
                same_base[] * "/oversized.json";
                max_bytes = 128,
            )
            @test occursin("128-byte limit", sprint(showerror, oversized.value))
        finally
            close(same_server)
            close(cross_server)
        end
    end

    @testset "non-schema cycles and Path Item siblings" begin
        cycle = OpenAPI.obj(
            "openapi" => "3.1.1",
            "info" => OpenAPI.obj("title" => "Cycle", "version" => "1"),
            "paths" => OpenAPI.obj(
                "/x" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "cycle",
                        "parameters" => Any[
                            OpenAPI.obj(
                                "\$ref" => "#/components/parameters/A",
                            ),
                        ],
                        "responses" => OpenAPI.obj(
                            "204" => OpenAPI.obj("description" => "empty"),
                        ),
                    ),
                ),
            ),
            "components" => OpenAPI.obj(
                "parameters" => OpenAPI.obj(
                    "A" => OpenAPI.obj(
                        "\$ref" => "#/components/parameters/B",
                    ),
                    "B" => OpenAPI.obj(
                        "\$ref" => "#/components/parameters/A",
                    ),
                ),
            ),
        )
        error = @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(cycle)
        @test any(
            diagnostic -> diagnostic.code === :reference_cycle,
            error.value.diagnostics,
        )

        siblings = OpenAPI.obj(
            "openapi" => "3.1.1",
            "info" => OpenAPI.obj("title" => "Path refs", "version" => "1"),
            "paths" => OpenAPI.obj(
                "/x" => OpenAPI.obj(
                    "\$ref" => "#/components/pathItems/Base",
                    "get" => OpenAPI.obj(
                        "operationId" => "local",
                        "responses" => OpenAPI.obj(
                            "204" => OpenAPI.obj("description" => "local"),
                        ),
                    ),
                ),
            ),
            "components" => OpenAPI.obj(
                "pathItems" => OpenAPI.obj(
                    "Base" => OpenAPI.obj(
                        "get" => OpenAPI.obj(
                            "operationId" => "base",
                            "responses" => OpenAPI.obj(
                                "204" => OpenAPI.obj("description" => "base"),
                            ),
                        ),
                    ),
                ),
            ),
        )
        @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(siblings)
        permissive = OpenAPI.normalize(siblings; strict = false)
        @test only(permissive.operations).id == "local"
        @test any(
            diagnostic -> diagnostic.code === :path_item_reference_siblings &&
                          diagnostic.severity === :warning,
            permissive.diagnostics,
        )
    end

    @testset "input resource limits" begin
        document = OpenAPI.obj(
            "openapi" => "3.1.1",
            "info" => OpenAPI.obj("title" => "Limits", "version" => "1"),
            "paths" => OpenAPI.obj(),
            "x-deep" => OpenAPI.obj(
                "one" => OpenAPI.obj(
                    "two" => OpenAPI.obj(
                        "three" => OpenAPI.obj("four" => true),
                    ),
                ),
            ),
        )
        @test_throws OpenAPI.OpenAPIError OpenAPI.load(
            JSON.json(document);
            max_depth = 3,
        )
        @test_throws OpenAPI.OpenAPIError OpenAPI.load(
            JSON.json(document);
            max_nodes = 5,
        )
        @test_throws ArgumentError OpenAPI.load(
            JSON.json(document);
            max_bytes = 8,
        )
    end
end
