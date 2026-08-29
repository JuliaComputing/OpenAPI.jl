semantic_empty_response() = OpenAPI.obj(
    "204" => OpenAPI.obj("description" => "empty"),
)

function semantic_operation(id; responses = semantic_empty_response(), kwargs...)
    operation = OpenAPI.obj("operationId" => String(id))
    responses === nothing || (operation["responses"] = responses)
    for (key, value) in kwargs
        operation[String(key)] = value
    end
    return operation
end

@testset "OpenAPI semantic coverage" begin
    @testset "OAS 3.2 methods and explicit generation deferrals" begin
        paths = OpenAPI.obj(
            "/items" => OpenAPI.obj(
                "query" => semantic_operation("queryItems"; responses = nothing),
                "additionalOperations" => OpenAPI.obj(
                    "PURGE" => semantic_operation("purgeItems"; responses = nothing),
                ),
            ),
            "/search" => OpenAPI.obj(
                "get" => semantic_operation(
                    "search";
                    parameters = Any[
                        OpenAPI.obj(
                            "name" => "query",
                            "in" => "querystring",
                            "required" => true,
                            "content" => OpenAPI.obj(
                                "application/x-www-form-urlencoded" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj("type" => "string"),
                                ),
                            ),
                        ),
                    ],
                ),
            ),
            "/events" => OpenAPI.obj(
                "get" => semantic_operation(
                    "events";
                    responses = OpenAPI.obj(
                        "200" => OpenAPI.obj(
                            "description" => "events",
                            "content" => OpenAPI.obj(
                                "application/jsonl" => OpenAPI.obj(
                                    "itemSchema" => OpenAPI.obj(
                                        "type" => "object",
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        document = minimal_openapi("3.2.0", paths)
        api = OpenAPI.normalize(document)
        methods = Dict(operation.id => operation.method for operation in api.operations)
        @test methods["queryItems"] === :QUERY
        @test methods["purgeItems"] === :PURGE
        @test isempty(only(filter(operation -> operation.id == "queryItems", api.operations)).responses)

        error = @test_throws OpenAPI.OpenAPIError OpenAPI.plan(api)
        codes = Set(diagnostic.code for diagnostic in error.value.diagnostics)
        @test :unsupported_querystring_generation in codes
        @test :unsupported_streaming_generation in codes
    end

    @testset "OAS 3.2 Media Type references and response headers" begin
        document = minimal_openapi(
            "3.2.0",
            OpenAPI.obj(
                "/x" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "getX";
                        responses = OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "summary" => "success",
                                "headers" => OpenAPI.obj(
                                    "Content-Type" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj("type" => "string"),
                                    ),
                                    "X-Rate" => OpenAPI.obj(
                                        "required" => true,
                                        "schema" => OpenAPI.obj("type" => "integer"),
                                    ),
                                ),
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "\$ref" => "#/components/mediaTypes/JsonValue",
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        document["components"] = OpenAPI.obj(
            "mediaTypes" => OpenAPI.obj(
                "JsonValue" => OpenAPI.obj(
                    "schema" => OpenAPI.obj("type" => "string"),
                ),
            ),
        )
        api = OpenAPI.normalize(document)
        response = only(only(api.operations).responses)
        @test response.summary == "success"
        @test response.description === nothing
        @test length(response.content) == 1
        @test response.content[1].schema !== nothing
        @test only(response.headers).name == "X-Rate"
        @test only(response.headers).required
        @test any(
            diagnostic -> diagnostic.code === :ignored_content_type_header,
            api.diagnostics,
        )
    end

    @testset "reserved request headers are ignored" begin
        operation = semantic_operation(
            "headers";
            parameters = Any[
                OpenAPI.obj(
                    "name" => name,
                    "in" => "header",
                    "schema" => OpenAPI.obj("type" => "string"),
                ) for name in ("Accept", "Content-Type", "Authorization")
            ],
        )
        api = OpenAPI.normalize(
            minimal_openapi(
                "3.1.1",
                OpenAPI.obj("/headers" => OpenAPI.obj("get" => operation)),
            ),
        )
        @test isempty(only(api.operations).parameters)
        @test count(
            diagnostic -> diagnostic.code === :ignored_header_parameter,
            api.diagnostics,
        ) == 3
    end

    @testset "semantic conflicts collect stable diagnostics" begin
        document = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/pets/{id}" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "duplicate";
                        parameters = Any[
                            OpenAPI.obj(
                                "name" => "id",
                                "in" => "path",
                                "required" => true,
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ],
                    ),
                ),
                "/pets/{name}" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "duplicate";
                        parameters = Any[
                            OpenAPI.obj(
                                "name" => "name",
                                "in" => "path",
                                "required" => true,
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ],
                    ),
                ),
            ),
        )
        error = @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(document)
        codes = Set(diagnostic.code for diagnostic in error.value.diagnostics)
        @test :ambiguous_path_template in codes
        @test :duplicate_operation_id in codes

        compatible = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/pets/{id}" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "byId";
                        parameters = Any[
                            OpenAPI.obj(
                                "name" => "id",
                                "in" => "path",
                                "required" => true,
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ],
                    ),
                ),
                "/pets/{name}" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "byName";
                        parameters = Any[
                            OpenAPI.obj(
                                "name" => "name",
                                "in" => "path",
                                "required" => true,
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ],
                    ),
                ),
            ),
        )
        permissive = OpenAPI.normalize(compatible; strict = false)
        @test length(permissive.operations) == 2
        warning = only(
            diagnostic for diagnostic in permissive.diagnostics if
            diagnostic.code === :ambiguous_path_template
        )
        @test warning.severity === :warning
        plan = OpenAPI.plan(permissive; strict = false)
        @test any(
            diagnostic -> diagnostic.code === :ambiguous_path_template,
            plan.diagnostics,
        )

        media = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/media" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "media";
                        responses = OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "media",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(),
                                    "Application/JSON" => OpenAPI.obj(),
                                    "not a media type" => OpenAPI.obj(),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        media_error = @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(media)
        media_codes = Set(diagnostic.code for diagnostic in media_error.value.diagnostics)
        @test :duplicate_media_type in media_codes
        @test :invalid_media_type in media_codes

        # Content keys differing only in parameters are distinct entries: the
        # Kubernetes OpenAPI v3 documents pair `application/json` with
        # `application/json;stream=watch` on every list operation.
        parameterized = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/media" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "media";
                        responses = OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "media",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(),
                                    "application/json;stream=watch" => OpenAPI.obj(),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        normalized_parameterized = OpenAPI.normalize(parameterized)
        parameterized_response =
            only(only(normalized_parameterized.operations).responses)
        @test [media.content_type for media in parameterized_response.content] ==
              ["application/json", "application/json;stream=watch"]
    end

    @testset "planning rejects incompatible styles and encodings" begin
        document = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/invalid" => OpenAPI.obj(
                    "post" => semantic_operation(
                        "invalid";
                        parameters = Any[
                            OpenAPI.obj(
                                "name" => "filter",
                                "in" => "query",
                                "style" => "deepObject",
                                "explode" => true,
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                            OpenAPI.obj(
                                "name" => "values",
                                "in" => "query",
                                "style" => "pipeDelimited",
                                "explode" => false,
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ],
                        requestBody = OpenAPI.obj(
                            "content" => OpenAPI.obj(
                                "multipart/mixed" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj(
                                        "type" => "object",
                                        "properties" => OpenAPI.obj(
                                            "known" => OpenAPI.obj("type" => "string"),
                                        ),
                                        "additionalProperties" => false,
                                    ),
                                    "encoding" => OpenAPI.obj(
                                        "unknown" => OpenAPI.obj(
                                            "contentType" => "text/plain",
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        error = @test_throws OpenAPI.OpenAPIError OpenAPI.plan(document)
        codes = Set(diagnostic.code for diagnostic in error.value.diagnostics)
        @test :invalid_deep_object_schema in codes
        @test :invalid_delimited_schema in codes
        @test :ignored_encoding_property in codes
        ignored = only(
            diagnostic for diagnostic in error.value.diagnostics if
            diagnostic.code === :ignored_encoding_property
        )
        @test ignored.severity === :warning
    end

    @testset "permissive vendor serialization compatibility" begin
        document = minimal_openapi(
            "3.0.4",
            OpenAPI.obj(
                "/items" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "items";
                        parameters = Any[
                            OpenAPI.obj(
                                "name" => "expand",
                                "in" => "query",
                                "style" => "deepObject",
                                "explode" => true,
                                "schema" => OpenAPI.obj(
                                    "type" => "array",
                                    "items" => OpenAPI.obj("type" => "string"),
                                ),
                            ),
                        ],
                    ),
                ),
            ),
        )
        @test_throws OpenAPI.OpenAPIError OpenAPI.plan(document)
        plan = OpenAPI.plan(document; strict = false)
        warning = only(
            diagnostic for diagnostic in plan.diagnostics if
            diagnostic.code === :invalid_deep_object_schema
        )
        @test warning.severity === :warning
        @test occursin("non-standard", warning.message)
    end

    @testset "encoding fields follow their media-type scope" begin
        document = minimal_openapi(
            "3.1.1",
            OpenAPI.obj(
                "/upload" => OpenAPI.obj(
                    "post" => semantic_operation(
                        "upload";
                        requestBody = OpenAPI.obj(
                            "content" => OpenAPI.obj(
                                "multipart/mixed" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj(
                                        "type" => "object",
                                        "properties" => OpenAPI.obj(
                                            "file" => OpenAPI.obj("type" => "string"),
                                        ),
                                    ),
                                    "encoding" => OpenAPI.obj(
                                        "file" => OpenAPI.obj(
                                            "style" => "form",
                                            "explode" => true,
                                            "allowReserved" => true,
                                            "headers" => OpenAPI.obj(
                                                "X-Part" => OpenAPI.obj(
                                                    "schema" => OpenAPI.obj(
                                                        "type" => "integer",
                                                    ),
                                                ),
                                            ),
                                        ),
                                    ),
                                ),
                                "application/x-www-form-urlencoded" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj(
                                        "type" => "object",
                                        "properties" => OpenAPI.obj(
                                            "file" => OpenAPI.obj("type" => "string"),
                                        ),
                                    ),
                                    "encoding" => OpenAPI.obj(
                                        "file" => OpenAPI.obj(
                                            "headers" => OpenAPI.obj(
                                                "X-Ignored" => OpenAPI.obj(
                                                    "schema" => OpenAPI.obj(
                                                        "type" => "string",
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
            ),
        )
        api = OpenAPI.normalize(document)
        codes = Set(diagnostic.code for diagnostic in api.diagnostics)
        @test :ignored_non_form_multipart_encoding_style in codes
        @test :ignored_form_encoding_headers in codes

        plan = OpenAPI.plan(api; name = "EncodingScopeClient")
        source = OpenAPI.client(plan)
        @test occursin("multipart_headers = NamedTuple()", source)
        @test occursin("name = \"X-Part\"", source)
        @test !occursin("name = \"X-Ignored\"", source)
    end

    @testset "security scopes and server names" begin
        document = minimal_openapi(
            "3.2.0",
            OpenAPI.obj(
                "/secure" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "secure";
                        security = Any[OpenAPI.obj("OAuth" => ["missing"])],
                    ),
                ),
            ),
        )
        document["servers"] = Any[
            OpenAPI.obj("name" => "same", "url" => "https://one.example"),
            OpenAPI.obj("name" => "same", "url" => "https://two.example"),
        ]
        document["components"] = OpenAPI.obj(
            "securitySchemes" => OpenAPI.obj(
                "OAuth" => OpenAPI.obj(
                    "type" => "oauth2",
                    "flows" => OpenAPI.obj(
                        "clientCredentials" => OpenAPI.obj(
                            "tokenUrl" => "https://auth.example/token",
                            "scopes" => OpenAPI.obj("read" => "read"),
                        ),
                    ),
                ),
            ),
        )
        error = @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(document)
        codes = Set(diagnostic.code for diagnostic in error.value.diagnostics)
        @test :unknown_oauth_scope in codes
        @test :duplicate_server_name in codes
    end

    @testset "externally declared security schemes" begin
        # The Security Requirement Object's names MUST correspond to declared
        # schemes, but the specification's multi-document pattern lets a
        # referenced document name schemes its entry document declares. Strict
        # mode enforces the MUST; permissive mode warns and generation excludes
        # the unknown scheme from credential enforcement.
        document = minimal_openapi(
            "3.0.3",
            OpenAPI.obj(
                "/things" => OpenAPI.obj(
                    "get" => semantic_operation(
                        "listThings";
                        responses = OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "ok",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj("type" => "string"),
                                    ),
                                ),
                            ),
                        ),
                        security = Any[
                            OpenAPI.obj("gatewayAuth" => Any[]),
                            OpenAPI.obj("localKey" => Any[]),
                        ],
                    ),
                ),
            ),
        )
        document["components"] = OpenAPI.obj(
            "securitySchemes" => OpenAPI.obj(
                "localKey" => OpenAPI.obj(
                    "type" => "apiKey",
                    "name" => "X-Key",
                    "in" => "header",
                ),
            ),
        )

        strict_error = @test_throws OpenAPI.OpenAPIError OpenAPI.normalize(document)
        @test any(
            diagnostic -> diagnostic.code === :unknown_security_scheme,
            strict_error.value.diagnostics,
        )

        permissive = OpenAPI.normalize(document; strict = false)
        warning = only(
            diagnostic for diagnostic in permissive.diagnostics if
            diagnostic.code === :unknown_security_scheme
        )
        @test warning.severity === :warning

        # the unknown scheme is excluded from the generated operation security:
        # its alternative becomes anonymous, and the declared scheme survives
        source = OpenAPI.client(permissive; name = "ExternalAuthClient", strict = false)
        @test occursin("security = ((),((name = \"localKey\", scopes = ()),)),", source)
        # the unknown scheme survives only inside the embedded raw document,
        # never as an enforceable descriptor or scheme entry
        @test !occursin("name = \"gatewayAuth\"", source)
        @test !occursin("\"gatewayAuth\" =>", source)
        @test occursin("\"localKey\" => (type = :apikey", source)
    end
end
