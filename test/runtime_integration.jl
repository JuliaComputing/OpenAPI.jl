function runtime_response(
    media::AbstractString,
    schema;
    description::AbstractString = "response",
    headers = nothing,
)
    response = OpenAPI.obj(
        "description" => String(description),
        "content" => OpenAPI.obj(
            String(media) => OpenAPI.obj("schema" => schema),
        ),
    )
    headers === nothing || (response["headers"] = headers)
    return response
end

function runtime_parameter(
    name,
    location,
    schema;
    required = true,
    style = nothing,
    explode = nothing,
    allow_reserved = false,
)
    parameter = OpenAPI.obj(
        "name" => String(name),
        "in" => String(location),
        "required" => required,
        "schema" => schema,
    )
    style === nothing || (parameter["style"] = String(style))
    explode === nothing || (parameter["explode"] = explode)
    allow_reserved && (parameter["allowReserved"] = true)
    return parameter
end

function captured_header(request, name::AbstractString, default = "")
    lowered = lowercase(name)
    index = findlast(pair -> lowercase(pair.first) == lowered, request.headers)
    return index === nothing ? default : request.headers[index].second
end

function captured_header_values(request, name::AbstractString)
    lowered = lowercase(name)
    return String[
        pair.second for pair in request.headers if lowercase(pair.first) == lowered
    ]
end

@testset "generated runtime HTTP integration" begin
    captures = Channel{Any}(64)
    handler = function (request)
        target = String(request.target)
        path = first(split(target, '?'; limit = 2))
        body = Vector{UInt8}(codeunits(String(request.body)))
        put!(
            captures,
            (
                method = String(request.method),
                target,
                headers = Pair{String,String}[
                    String(key) => String(value) for (key, value) in request.headers
                ],
                body,
            ),
        )
        if startswith(path, "/status/201")
            return HTTP.Response(
                201,
                ["Content-Type" => "application/json", "X-Rate" => "7"],
                """{"kind":"exact","id":1}""",
            )
        elseif startswith(path, "/status/202")
            return HTTP.Response(
                202,
                ["Content-Type" => "application/vnd.runtime+json", "X-Rate" => "8"],
                """{"kind":"range","queued":true}""",
            )
        elseif startswith(path, "/failure/duplicate")
            return HTTP.Response(
                500,
                ["Content-Type" => "application/json"],
                """{"error":"first","error":"second"}""",
            )
        elseif startswith(path, "/failure/binary")
            return HTTP.Response(
                500,
                ["Content-Type" => "text/plain"],
                UInt8[0xff, 0x00],
            )
        elseif startswith(path, "/unexpected")
            return HTTP.Response(200, ["Content-Type" => "text/plain"], "surprise")
        elseif startswith(path, "/wrong-content")
            return HTTP.Response(200, ["Content-Type" => "text/html"], "<p>wrong</p>")
        elseif startswith(path, "/sloppy-content")
            return HTTP.Response(200, ["Content-Type" => "text/plain"], """{"ok":true}""")
        elseif startswith(path, "/ambiguous-content")
            return HTTP.Response(200, ["Content-Type" => "application/xml"], "<x/>")
        elseif startswith(path, "/no-content-type")
            return HTTP.Response(200, Pair{String,String}[], """{"ok":true}""")
        elseif startswith(path, "/undocumented/204")
            return HTTP.Response(204)
        elseif startswith(path, "/undocumented/201")
            return HTTP.Response(
                201,
                ["Content-Type" => "application/json"],
                """{"extra":true}""",
            )
        elseif startswith(path, "/undocumented/404")
            return HTTP.Response(404, ["Content-Type" => "text/plain"], "missing")
        elseif startswith(path, "/bad-text")
            return HTTP.Response(
                200,
                ["Content-Type" => "text/plain"],
                UInt8[0xff],
            )
        elseif startswith(path, "/drift")
            return HTTP.Response(
                200,
                ["Content-Type" => "application/json"],
                """{"items":[{"probe":{"lastProbeTime":null,"newServerField":true}}]}""",
            )
        elseif startswith(path, "/sequence")
            return HTTP.Response(
                200,
                ["Content-Type" => "application/x-ndjson"],
                "1\n2\n",
            )
        elseif startswith(path, "/custom")
            return HTTP.Response(
                200,
                ["Content-Type" => "application/x-runtime"],
                body,
            )
        elseif startswith(path, "/json")
            return HTTP.Response(200, ["Content-Type" => "application/json"], body)
        elseif startswith(path, "/form") || startswith(path, "/multipart")
            return HTTP.Response(200, ["Content-Type" => "text/plain"], "accepted")
        elseif startswith(path, "/secure")
            return HTTP.Response(200, ["Content-Type" => "text/plain"], "authorized")
        end
        return HTTP.Response(
            200,
            ["Content-Type" => "application/json"],
            """{"ok":true}""",
        )
    end

    server = HTTP.serve!(handler, "127.0.0.1", 0; verbose = false)
    try
        port = HTTP.port(server)
        base = "http://127.0.0.1:$port"
        string_schema = OpenAPI.obj("type" => "string")
        string_array = OpenAPI.obj(
            "type" => "array",
            "items" => string_schema,
        )
        payload_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["name", "count"],
            "properties" => OpenAPI.obj(
                "name" => string_schema,
                "count" => OpenAPI.obj("type" => "integer"),
            ),
            "additionalProperties" => false,
        )
        form_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["tags", "flag"],
            "properties" => OpenAPI.obj(
                "tags" => string_array,
                "flag" => OpenAPI.obj("type" => "boolean"),
                "note" => string_schema,
            ),
            "additionalProperties" => false,
        )
        nested_multipart_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["nested_file", "label"],
            "properties" => OpenAPI.obj(
                "nested_file" => OpenAPI.obj(
                    "type" => "string",
                    "format" => "binary",
                ),
                "label" => string_schema,
            ),
            "additionalProperties" => false,
        )
        multipart_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["file", "note", "bundle"],
            "properties" => OpenAPI.obj(
                "file" => OpenAPI.obj("type" => "string", "format" => "binary"),
                "note" => string_schema,
                "bundle" => nested_multipart_schema,
            ),
            "additionalProperties" => false,
        )
        exact_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["kind", "id"],
            "properties" => OpenAPI.obj(
                "kind" => OpenAPI.obj("const" => "exact"),
                "id" => OpenAPI.obj("type" => "integer"),
            ),
            "additionalProperties" => false,
        )
        range_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["kind", "queued"],
            "properties" => OpenAPI.obj(
                "kind" => OpenAPI.obj("const" => "range"),
                "queued" => OpenAPI.obj("type" => "boolean"),
            ),
            "additionalProperties" => false,
        )
        event_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["kind", "seq"],
            "properties" => OpenAPI.obj(
                "kind" => string_schema,
                "seq" => OpenAPI.obj("type" => "integer"),
            ),
            "additionalProperties" => false,
        )
        event_list_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["items"],
            "properties" => OpenAPI.obj(
                "items" => OpenAPI.obj("type" => "array", "items" => event_schema),
            ),
            "additionalProperties" => false,
        )
        probe_schema = OpenAPI.obj(
            "type" => "object",
            "properties" => OpenAPI.obj(
                "lastProbeTime" => OpenAPI.obj(
                    "type" => "string",
                    "format" => "date-time",
                ),
            ),
            "additionalProperties" => false,
        )
        pod_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["probe"],
            "properties" => OpenAPI.obj(
                "probe" => OpenAPI.obj("\$ref" => "#/components/schemas/Probe"),
            ),
            "additionalProperties" => false,
        )
        pod_list_schema = OpenAPI.obj(
            "type" => "object",
            "required" => ["items"],
            "properties" => OpenAPI.obj(
                "items" => OpenAPI.obj(
                    "type" => "array",
                    "items" => OpenAPI.obj("\$ref" => "#/components/schemas/Pod"),
                ),
            ),
            "additionalProperties" => false,
        )

        paths = OpenAPI.obj(
            "/styles/{simple}/{label}/{matrix}" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "serializeStyles",
                    "parameters" => Any[
                        runtime_parameter(
                            "simple",
                            "path",
                            string_array;
                            style = "simple",
                            explode = false,
                        ),
                        runtime_parameter(
                            "label",
                            "path",
                            string_schema;
                            style = "label",
                            explode = false,
                        ),
                        runtime_parameter(
                            "matrix",
                            "path",
                            string_array;
                            style = "matrix",
                            explode = true,
                        ),
                        runtime_parameter(
                            "qform",
                            "query",
                            string_array;
                            style = "form",
                            explode = false,
                        ),
                        runtime_parameter(
                            "spaces",
                            "query",
                            string_array;
                            style = "spaceDelimited",
                            explode = false,
                        ),
                        runtime_parameter(
                            "pipes",
                            "query",
                            string_array;
                            style = "pipeDelimited",
                            explode = false,
                        ),
                        runtime_parameter(
                            "reserved",
                            "query",
                            string_schema;
                            style = "form",
                            allow_reserved = true,
                        ),
                        runtime_parameter(
                            "xmeta",
                            "header",
                            string_schema;
                            style = "simple",
                        ),
                        runtime_parameter(
                            "crumb",
                            "cookie",
                            string_array;
                            style = "form",
                            explode = true,
                        ),
                    ],
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", OpenAPI.obj()),
                    ),
                ),
            ),
            "/json" => OpenAPI.obj(
                "post" => OpenAPI.obj(
                    "operationId" => "submitJson",
                    "requestBody" => OpenAPI.obj(
                        "required" => true,
                        "content" => OpenAPI.obj(
                            "application/json" => OpenAPI.obj(
                                "schema" => OpenAPI.obj(
                                    "\$ref" => "#/components/schemas/Payload",
                                ),
                            ),
                        ),
                    ),
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response(
                            "application/json",
                            OpenAPI.obj("\$ref" => "#/components/schemas/Payload"),
                        ),
                    ),
                ),
            ),
            "/form" => OpenAPI.obj(
                "post" => OpenAPI.obj(
                    "operationId" => "submitForm",
                    "requestBody" => OpenAPI.obj(
                        "required" => true,
                        "content" => OpenAPI.obj(
                            "application/x-www-form-urlencoded" => OpenAPI.obj(
                                "schema" => form_schema,
                                "encoding" => OpenAPI.obj(
                                    "tags" => OpenAPI.obj(
                                        "style" => "form",
                                        "explode" => true,
                                    ),
                                ),
                            ),
                        ),
                    ),
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("text/plain", string_schema),
                    ),
                ),
            ),
            "/multipart" => OpenAPI.obj(
                "post" => OpenAPI.obj(
                    "operationId" => "submitMultipart",
                    "requestBody" => OpenAPI.obj(
                        "required" => true,
                        "content" => OpenAPI.obj(
                            "multipart/form-data" => OpenAPI.obj(
                                "schema" => multipart_schema,
                                "encoding" => OpenAPI.obj(
                                    "file" => OpenAPI.obj(
                                        "contentType" => "application/octet-stream, image/png",
                                        "headers" => OpenAPI.obj(
                                            "X-Part-Index" => OpenAPI.obj(
                                                "required" => true,
                                                "schema" => OpenAPI.obj(
                                                    "type" => "integer",
                                                ),
                                            ),
                                            "X-Part-Meta" => OpenAPI.obj(
                                                "content" => OpenAPI.obj(
                                                    "application/json" => OpenAPI.obj(
                                                        "schema" => OpenAPI.obj(
                                                            "type" => "object",
                                                        ),
                                                    ),
                                                ),
                                            ),
                                        ),
                                    ),
                                    "bundle" => OpenAPI.obj(
                                        "contentType" => "multipart/form-data",
                                        "encoding" => OpenAPI.obj(
                                            "nested_file" => OpenAPI.obj(
                                                "contentType" => "application/octet-stream",
                                                "headers" => OpenAPI.obj(
                                                    "X-Nested" => OpenAPI.obj(
                                                        "required" => true,
                                                        "schema" => OpenAPI.obj(
                                                            "type" => "integer",
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
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("text/plain", string_schema),
                    ),
                ),
            ),
            "/status/{code}" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "statusResult",
                    "parameters" => Any[
                        runtime_parameter(
                            "code",
                            "path",
                            OpenAPI.obj("type" => "integer"),
                        ),
                    ],
                    "responses" => OpenAPI.obj(
                        "201" => runtime_response(
                            "application/json",
                            exact_schema;
                            headers = OpenAPI.obj(
                                "X-Rate" => OpenAPI.obj(
                                    "required" => true,
                                    "schema" => OpenAPI.obj("type" => "integer"),
                                ),
                            ),
                        ),
                        "2XX" => runtime_response(
                            "application/*+json",
                            range_schema;
                            headers = OpenAPI.obj(
                                "X-Rate" => OpenAPI.obj(
                                    "required" => true,
                                    "schema" => OpenAPI.obj("type" => "integer"),
                                ),
                            ),
                        ),
                        "default" => runtime_response(
                            "application/problem+json",
                            OpenAPI.obj(),
                        ),
                    ),
                ),
            ),
            "/failure/{kind}" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "failure",
                    "parameters" => Any[
                        runtime_parameter("kind", "path", string_schema),
                    ],
                    "responses" => OpenAPI.obj(
                        "default" => OpenAPI.obj(
                            "description" => "failure",
                            "content" => OpenAPI.obj(
                                "application/json" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj(),
                                ),
                                "text/plain" => OpenAPI.obj(
                                    "schema" => string_schema,
                                ),
                            ),
                        ),
                    ),
                ),
            ),
            "/unexpected" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "unexpectedBody",
                    "responses" => OpenAPI.obj(
                        "200" => OpenAPI.obj("description" => "empty"),
                    ),
                ),
            ),
            "/wrong-content" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "wrongContent",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", OpenAPI.obj()),
                    ),
                ),
            ),
            "/sloppy-content" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "sloppyContent",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", OpenAPI.obj()),
                    ),
                ),
            ),
            "/ambiguous-content" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "ambiguousContent",
                    "responses" => OpenAPI.obj(
                        "200" => OpenAPI.obj(
                            "description" => "two media types",
                            "content" => OpenAPI.obj(
                                "application/json" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj(),
                                ),
                                "text/plain" => OpenAPI.obj(
                                    "schema" => string_schema,
                                ),
                            ),
                        ),
                    ),
                ),
            ),
            "/no-content-type" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "missingContentType",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", OpenAPI.obj()),
                    ),
                ),
            ),
            "/undocumented/{code}" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "undocumentedStatus",
                    "parameters" => Any[
                        runtime_parameter(
                            "code",
                            "path",
                            OpenAPI.obj("type" => "integer"),
                        ),
                    ],
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", OpenAPI.obj()),
                    ),
                ),
            ),
            "/bad-text" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "badText",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("text/plain", string_schema),
                    ),
                ),
            ),
            "/drift" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "driftList",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response(
                            "application/json",
                            OpenAPI.obj("\$ref" => "#/components/schemas/PodList"),
                        ),
                    ),
                ),
            ),
            "/sequence" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "sequence",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response(
                            "application/x-ndjson",
                            OpenAPI.obj(
                                "type" => "array",
                                "items" => OpenAPI.obj("type" => "integer"),
                            ),
                        ),
                    ),
                ),
            ),
            "/stream/watch" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "watchStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", event_schema),
                    ),
                ),
            ),
            "/stream/custom-watch" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "customWatchStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response(
                            "application/json; stream=watch",
                            event_list_schema,
                        ),
                    ),
                ),
            ),
            "/stream/k8s-watch" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "k8sWatchStream",
                    "responses" => OpenAPI.obj(
                        "200" => OpenAPI.obj(
                            "description" => "response",
                            "content" => OpenAPI.obj(
                                "application/json" => OpenAPI.obj(
                                    "schema" => event_list_schema,
                                ),
                                "application/json;stream=watch" => OpenAPI.obj(
                                    "schema" => event_list_schema,
                                ),
                            ),
                        ),
                    ),
                ),
            ),
            "/stream/logs" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "logStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response(
                            "application/x-ndjson",
                            OpenAPI.obj(
                                "type" => "array",
                                "items" => OpenAPI.obj("type" => "integer"),
                            ),
                        ),
                    ),
                ),
            ),
            "/stream/seq" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "seqStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response(
                            "application/json-seq",
                            OpenAPI.obj(
                                "type" => "array",
                                "items" => string_schema,
                            ),
                        ),
                    ),
                ),
            ),
            "/stream/truncated" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "truncatedStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", event_schema),
                    ),
                ),
            ),
            "/stream/invalid" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "invalidStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", event_schema),
                    ),
                ),
            ),
            "/stream/missing" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "missingStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", event_schema),
                    ),
                ),
            ),
            "/stream/forever" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "foreverStream",
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response("application/json", event_schema),
                    ),
                ),
            ),
            "/custom" => OpenAPI.obj(
                "post" => OpenAPI.obj(
                    "operationId" => "customCodec",
                    "requestBody" => OpenAPI.obj(
                        "required" => true,
                        "content" => OpenAPI.obj(
                            "application/x-runtime" => OpenAPI.obj(
                                "schema" => string_schema,
                            ),
                        ),
                    ),
                    "responses" => OpenAPI.obj(
                        "200" => runtime_response(
                            "application/x-runtime",
                            string_schema,
                        ),
                    ),
                ),
            ),
        )

        security_response = OpenAPI.obj(
            "200" => runtime_response("text/plain", string_schema),
        )
        paths["/secure/and"] = OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "secureAnd",
                "security" => Any[
                    OpenAPI.obj("HeaderKey" => String[], "CookieKey" => String[]),
                ],
                "responses" => security_response,
            ),
        )
        paths["/secure/or"] = OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "secureOr",
                "security" => Any[
                    OpenAPI.obj("QueryKey" => String[]),
                    OpenAPI.obj("OAuth" => ["read"]),
                ],
                "responses" => security_response,
            ),
        )
        paths["/secure/basic"] = OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "secureBasic",
                "security" => Any[OpenAPI.obj("Basic" => String[])],
                "responses" => security_response,
            ),
        )
        paths["/secure/custom"] = OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "secureCustom",
                "security" => Any[OpenAPI.obj("Signature" => String[])],
                "responses" => security_response,
            ),
        )
        paths["/secure/mtls"] = OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "secureMtls",
                "security" => Any[OpenAPI.obj("Mutual" => ["admin"])],
                "responses" => security_response,
            ),
        )

        document = OpenAPI.obj(
            "openapi" => "3.2.0",
            "info" => OpenAPI.obj("title" => "Runtime API", "version" => "1"),
            "servers" => Any[
                OpenAPI.obj(
                    "name" => "local",
                    "url" => "http://127.0.0.1:{port}",
                    "variables" => OpenAPI.obj(
                        "port" => OpenAPI.obj(
                            "default" => string(port),
                            "enum" => [string(port)],
                        ),
                    ),
                ),
                OpenAPI.obj("name" => "relative", "url" => "/v2"),
            ],
            "paths" => paths,
            "components" => OpenAPI.obj(
                "schemas" => OpenAPI.obj(
                    "Payload" => payload_schema,
                    "Probe" => probe_schema,
                    "Pod" => pod_schema,
                    "PodList" => pod_list_schema,
                ),
                "securitySchemes" => OpenAPI.obj(
                    "HeaderKey" => OpenAPI.obj(
                        "type" => "apiKey",
                        "in" => "header",
                        "name" => "X-API-Key",
                    ),
                    "CookieKey" => OpenAPI.obj(
                        "type" => "apiKey",
                        "in" => "cookie",
                        "name" => "sid",
                    ),
                    "QueryKey" => OpenAPI.obj(
                        "type" => "apiKey",
                        "in" => "query",
                        "name" => "access_key",
                    ),
                    "Basic" => OpenAPI.obj("type" => "http", "scheme" => "basic"),
                    "OAuth" => OpenAPI.obj(
                        "type" => "oauth2",
                        "flows" => OpenAPI.obj(
                            "clientCredentials" => OpenAPI.obj(
                                "tokenUrl" => "https://auth.example/token",
                                "scopes" => OpenAPI.obj("read" => "read access"),
                            ),
                        ),
                    ),
                    "Signature" => OpenAPI.obj(
                        "type" => "http",
                        "scheme" => "Signature",
                    ),
                    "Mutual" => OpenAPI.obj("type" => "mutualTLS"),
                ),
            ),
        )

        source = OpenAPI.client(document; name = "RuntimeHTTPClient")
        @test source == OpenAPI.client(document; name = "RuntimeHTTPClient")
        host = Module(:RuntimeHTTPClientHost)
        Base.include_string(host, source, "RuntimeHTTPClient.jl")
        C = Base.invokelatest(getfield, host, :RuntimeHTTPClient)

        call(name, args...; kwargs...) =
            Base.invokelatest(
                isdefined(C, name) ? getfield(C, name) :
                getfield(OpenAPI.Runtime, name),
                args...;
                kwargs...,
            )
        take_request() = take!(captures)
        client = C.Client()

        @testset "parameters, servers, and request overrides" begin
            result = call(
                :serializestyles,
                ["a", "b"],
                "dot/slash",
                ["x", "y"];
                qform = ["a", "b"],
                spaces = ["a", "b"],
                pipes = ["a", "b"],
                reserved = "a/b:c",
                xmeta = "metadata",
                crumb = ["c", "d"],
                client,
                request_headers = ["X-Request" => "yes", "Accept" => "custom/type"],
                request_options = (; status_exception = true),
                with_http_info = true,
            )
            request = take_request()
            @test request.method == "GET"
            @test request.target ==
                  "/styles/a,b/.dot%2Fslash/;matrix=x;matrix=y?qform=a,b&spaces=a%20b&pipes=a%7Cb&reserved=a/b:c"
            @test captured_header(request, "xmeta") == "metadata"
            @test captured_header(request, "X-Request") == "yes"
            @test captured_header(request, "Cookie") == "crumb=c&crumb=d"
            @test captured_header(request, "Accept") == "custom/type"
            @test result.status == 200
            @test result.body["ok"] === true

            operation = C._OP_serializestyles
            relative = C.Client(; server_name = "relative")
            @test call(:_server_for, relative, operation) == base * "/v2"
            @test_throws ArgumentError call(
                :_server_for,
                C.Client(; server_name = "missing"),
                operation,
            )
            @test_throws ArgumentError call(
                :_server_for,
                C.Client(; server_variables = Dict("port" => "1")),
                operation,
            )
        end

        @testset "JSON, form, multipart, sequential, and custom bodies" begin
            payload_type = first(C._OP_submitjson.request.media)[2]
            payload = call(:_decode, payload_type, Dict("name" => "Ada", "count" => 2))
            decoded = call(
                :submitjson,
                payload;
                client,
                request_options = (; body = "wrong"),
            )
            request = take_request()
            @test JSON.parse(String(request.body)) == Dict("name" => "Ada", "count" => 2)
            @test decoded.name == "Ada"
            @test decoded.count == 2

            form_type = first(C._OP_submitform.request.media)[2]
            form = Base.invokelatest(form_type; tags = ["a", "b"], flag = true)
            @test call(:submitform, form; client) == "accepted"
            request = take_request()
            form_text = String(request.body)
            @test occursin("tags=a", form_text)
            @test occursin("tags=b", form_text)
            @test occursin("flag=true", form_text)
            @test captured_header(request, "Content-Type") ==
                  "application/x-www-form-urlencoded"

            multipart_type = first(C._OP_submitmultipart.request.media)[2]
            upload = C.Upload(
                UInt8[0x00, 0x01, 0xff];
                filename = "data.bin",
                content_type = "application/octet-stream",
                headers = ["X-Part" => "yes"],
            )
            multipart = Base.invokelatest(
                multipart_type;
                file = upload,
                note = "hello",
                bundle = Base.invokelatest(
                    fieldtype(multipart_type, :bundle);
                    nested_file = C.Upload(
                        UInt8[0x02, 0x03];
                        filename = "nested.bin",
                    ),
                    label = "inside",
                ),
            )
            @test call(
                :submitmultipart,
                multipart;
                client,
                multipart_headers = Dict(
                    "file" => Dict(
                        "X-Part-Index" => 7,
                        "x-part-meta" => Dict("source" => "test"),
                    ),
                    "bundle" => C.MultipartPartHeaders(
                        ;
                        parts = Dict(
                            "nested_file" => Dict("X-Nested" => 9),
                        ),
                    ),
                ),
            ) == "accepted"
            request = take_request()
            multipart_text = String(request.body)
            @test occursin("filename=\"data.bin\"", multipart_text)
            @test occursin("Content-Type: application/octet-stream", multipart_text)
            @test occursin("X-Part: yes", multipart_text)
            @test occursin("X-Part-Index: 7", multipart_text)
            @test occursin("X-Part-Meta: {\"source\":\"test\"}", multipart_text)
            @test occursin("filename=\"nested.bin\"", multipart_text)
            @test occursin("X-Nested: 9", multipart_text)
            @test occursin("inside", multipart_text)
            @test occursin("hello", multipart_text)
            @test startswith(
                captured_header(request, "Content-Type"),
                "multipart/form-data; boundary=",
            )
            missing_header = @test_throws ArgumentError call(
                :submitmultipart,
                multipart;
                client,
            )
            @test occursin("required multipart header", missing_header.value.msg)
            unknown_header = @test_throws ArgumentError call(
                :submitmultipart,
                multipart;
                client,
                multipart_headers = Dict(
                    "file" => Dict(
                        "X-Part-Index" => 7,
                        "X-Unknown" => "no",
                    ),
                ),
            )
            @test occursin("not documented", unknown_header.value.msg)

            @test call(:sequence; client) == [1, 2]
            take_request()

            @test call(:customcodec, "MiXeD"; client) == "MiXeD"
            request = take_request()
            @test String(request.body) == "MiXeD"
            C.codec!(
                client,
                "application/x-runtime";
                encode = (value, _) -> uppercase(value),
                decode = (bytes, _) -> lowercase(String(bytes)),
            )
            @test call(:customcodec, "MiXeD"; client) == "mixed"
            request = take_request()
            @test String(request.body) == "MIXED"
        end

        @testset "response selection, headers, and safe errors" begin
            exact = call(:statusresult, 201; client, with_http_info = true)
            take_request()
            @test exact.status == 201
            @test exact.body.kind == "exact"
            @test exact.body.id == 1
            @test exact.decoded_headers["X-Rate"] == 7

            range = call(:statusresult, 202; client, with_http_info = true)
            take_request()
            @test range.status == 202
            @test range.body.kind == "range"
            @test range.body.queued === true
            @test range.decoded_headers["X-Rate"] == 8

            duplicate = @test_throws C.ApiError call(
                :failure,
                "duplicate";
                client,
                request_options = (; status_exception = true, retry = false),
            )
            take_request()
            @test duplicate.value.status == 500
            @test duplicate.value.decoded === nothing
            @test duplicate.value.decode_error isa C.DecodeError
            @test occursin("duplicate JSON object key", sprint(showerror, duplicate.value))

            binary = @test_throws C.ApiError call(
                :failure,
                "binary";
                client,
                request_options = (; retry = false),
            )
            take_request()
            @test binary.value.body == UInt8[0xff, 0x00]
            @test binary.value.decode_error isa C.DecodeError
            @test occursin("binary bytes", sprint(showerror, binary.value))

            @test_throws C.UnexpectedBody call(:unexpectedbody; client)
            take_request()
            # A misreported Content-Type falls back to the only documented
            # media type, so the html body fails JSON decoding rather than
            # content-type selection.
            @test_throws C.DecodeError call(:wrongcontent; client)
            take_request()
            sloppy = call(:sloppycontent; client)
            take_request()
            @test sloppy["ok"] === true
            @test_throws C.UnexpectedContentType call(:ambiguouscontent; client)
            take_request()
            missing_content_type = call(:missingcontenttype; client)
            take_request()
            @test missing_content_type["ok"] === true
            @test_throws C.DecodeError call(:badtext; client)
            take_request()

            @test_throws C.SchemaValidationError call(:driftlist; client)
            take_request()
            tolerant_client = C.Client(; validate_responses = false)
            drifted = call(:driftlist; client = tolerant_client)
            take_request()
            @test drifted.items[1].probe.lastprobetime === nothing

            @test call(:undocumentedstatus, 204; client) === nothing
            take_request()
            undocumented_bytes = call(:undocumentedstatus, 201; client)
            take_request()
            @test undocumented_bytes isa Vector{UInt8}
            @test JSON.parse(String(copy(undocumented_bytes)))["extra"] === true
            undocumented_error = @test_throws C.ApiError call(
                :undocumentedstatus,
                404;
                client,
                request_options = (; retry = false),
            )
            take_request()
            @test undocumented_error.value.status == 404
            @test undocumented_error.value.body == Vector{UInt8}(codeunits("missing"))
        end

        @testset "streaming responses" begin
            # A raw chunked HTTP/1.1 server gives the tests exact control over
            # how response bytes split across the wire.
            raw_server = Sockets.listen(Sockets.IPv4("127.0.0.1"), 0)
            raw_port = Sockets.getsockname(raw_server)[2]
            raw_client = C.Client("http://127.0.0.1:$raw_port")
            send_chunk = (socket, text) -> begin
                write(socket, string(ncodeunits(text), base = 16), "\r\n", text, "\r\n")
                flush(socket)
            end
            chunked_head = (media) ->
                "HTTP/1.1 200 OK\r\nContent-Type: $media\r\nTransfer-Encoding: chunked\r\n\r\n"
            finish_chunks = (socket) -> begin
                write(socket, "0\r\n\r\n")
                flush(socket)
            end
            forever_stopped = Channel{Nothing}(1)
            accept_task = @async while isopen(raw_server)
                socket = try
                    Sockets.accept(raw_server)
                catch
                    break
                end
                @async try
                    request_line = readline(socket)
                    while !isempty(readline(socket))
                    end
                    path = split(request_line, ' ')[2]
                    if startswith(path, "/stream/custom-watch")
                        write(socket, chunked_head("application/json; stream=watch"))
                        flush(socket)
                        send_chunk(socket, """{"kind":"ADDED","seq":10}\n""")
                        send_chunk(socket, """{"kind":"DELETED","seq":11}""")
                        finish_chunks(socket)
                    elseif startswith(path, "/stream/watch")
                        write(socket, chunked_head("application/json"))
                        flush(socket)
                        # one item split across two chunks, then two more items
                        send_chunk(socket, """{"kind":"ADDED",""")
                        sleep(0.05)
                        send_chunk(socket, """ "seq":1}\n{"kind":"MODIFIED","seq":2}\n""")
                        sleep(0.05)
                        send_chunk(socket, """{"kind":"DELETED","seq":3}""")
                        finish_chunks(socket)
                    elseif startswith(path, "/stream/k8s-watch")
                        # The Kubernetes apiserver replies with the bare media
                        # type even when the request selected the parameterized
                        # stream=watch variant.
                        write(socket, chunked_head("application/json"))
                        flush(socket)
                        send_chunk(socket, """{"kind":"ADDED","seq":21}\n""")
                        send_chunk(socket, """{"kind":"DELETED","seq":22}""")
                        finish_chunks(socket)
                    elseif startswith(path, "/stream/logs")
                        write(socket, chunked_head("application/x-ndjson"))
                        flush(socket)
                        send_chunk(socket, "1\n2\n")
                        sleep(0.05)
                        send_chunk(socket, "3")
                        finish_chunks(socket)
                    elseif startswith(path, "/stream/seq")
                        write(socket, chunked_head("application/json-seq"))
                        flush(socket)
                        send_chunk(socket, "\x1e\"alpha\"\n\x1e\"be")
                        sleep(0.05)
                        send_chunk(socket, "ta\"\n")
                        finish_chunks(socket)
                    elseif startswith(path, "/stream/truncated")
                        write(socket, chunked_head("application/json"))
                        flush(socket)
                        send_chunk(socket, """{"kind":"ADDED","seq":1}\n{"kind":"MOD""")
                        finish_chunks(socket)
                    elseif startswith(path, "/stream/invalid")
                        write(socket, chunked_head("application/json"))
                        flush(socket)
                        send_chunk(socket, """{"kind":"ADDED","seq":"nope"}""")
                        finish_chunks(socket)
                    elseif startswith(path, "/stream/missing")
                        body = """{"error":"nope"}"""
                        write(
                            socket,
                            "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\n" *
                            "Content-Length: $(ncodeunits(body))\r\n\r\n$body",
                        )
                        flush(socket)
                    elseif startswith(path, "/stream/forever")
                        try
                            write(socket, chunked_head("application/json"))
                            flush(socket)
                            send_chunk(socket, """{"kind":"TICK","seq":1}\n""")
                            read(socket, 1)
                        finally
                            put!(forever_stopped, nothing)
                        end
                    end
                    close(socket)
                catch
                    close(socket)
                end
            end
            try
                watch_channel = Channel{Any}(16)
                watch_info = call(
                    :watchstream;
                    client = raw_client,
                    stream_to = watch_channel,
                    with_http_info = true,
                )
                @test watch_info.status == 200
                @test watch_info.body === watch_channel
                watch_items = collect(watch_channel)
                @test [(item.kind, item.seq) for item in watch_items] ==
                      [("ADDED", 1), ("MODIFIED", 2), ("DELETED", 3)]

                invalid_custom_channel = Channel{Any}(16)
                call(
                    :customwatchstream;
                    client = raw_client,
                    stream_to = invalid_custom_channel,
                )
                @test_throws C.SchemaValidationError take!(invalid_custom_channel)

                C.codec!(
                    raw_client,
                    "Application/JSON; STREAM=watch";
                    decode = (bytes, media) -> begin
                        value = JSON.parse(String(bytes))
                        return (; kind = value["kind"], seq = value["seq"], media)
                    end,
                )
                custom_channel = Channel{Any}(16)
                call(:customwatchstream; client = raw_client, stream_to = custom_channel)
                custom_items = collect(custom_channel)
                @test [(item.kind, item.seq) for item in custom_items] ==
                      [("ADDED", 10), ("DELETED", 11)]
                @test all(
                    item -> item.media == "application/json; stream=watch",
                    custom_items,
                )

                # The parameter-specific codec must not replace the normal
                # application/json decoder.
                second_watch_channel = Channel{Any}(16)
                call(:watchstream; client = raw_client, stream_to = second_watch_channel)
                @test [(item.kind, item.seq) for item in collect(second_watch_channel)] ==
                      [("ADDED", 1), ("MODIFIED", 2), ("DELETED", 3)]

                # A deployed watch server replies with the bare media type, so
                # the parameterized codec fires for the calls that selected the
                # variant via `accept` ...
                k8s_channel = Channel{Any}(16)
                call(
                    :k8swatchstream;
                    client = raw_client,
                    stream_to = k8s_channel,
                    accept = "application/json;stream=watch",
                )
                k8s_items = collect(k8s_channel)
                @test [(item.kind, item.seq) for item in k8s_items] ==
                      [("ADDED", 21), ("DELETED", 22)]
                @test all(
                    item -> item.media == "application/json;stream=watch",
                    k8s_items,
                )

                # ... and not for calls that did not, which decode against the
                # documented List schema as before.
                bare_k8s_channel = Channel{Any}(16)
                call(:k8swatchstream; client = raw_client, stream_to = bare_k8s_channel)
                @test_throws C.SchemaValidationError take!(bare_k8s_channel)

                log_channel = Channel{Any}(16)
                @test call(:logstream; client = raw_client, stream_to = log_channel) ===
                      log_channel
                log_items = collect(log_channel)
                @test log_items == [1, 2, 3]
                @test all(item -> item isa Int64, log_items)

                seq_channel = Channel{Any}(16)
                call(:seqstream; client = raw_client, stream_to = seq_channel)
                @test collect(seq_channel) == ["alpha", "beta"]

                truncated_channel = Channel{Any}(16)
                call(:truncatedstream; client = raw_client, stream_to = truncated_channel)
                first_event = take!(truncated_channel)
                @test (first_event.kind, first_event.seq) == ("ADDED", 1)
                @test_throws C.DecodeError take!(truncated_channel)

                invalid_channel = Channel{Any}(16)
                call(:invalidstream; client = raw_client, stream_to = invalid_channel)
                @test_throws C.SchemaValidationError take!(invalid_channel)

                missing_channel = Channel{Any}(16)
                missing_error = @test_throws C.ApiError call(
                    :missingstream;
                    client = raw_client,
                    stream_to = missing_channel,
                )
                @test missing_error.value.status == 404
                @test JSON.parse(String(copy(missing_error.value.body)))["error"] ==
                      "nope"

                # Closing the channel from the consumer side aborts the
                # transfer; the call itself already returned at the response
                # head, so an endless stream does not block anything.
                forever_channel = Channel{Any}(2)
                call(:foreverstream; client = raw_client, stream_to = forever_channel)
                first_tick = take!(forever_channel)
                @test first_tick.kind == "TICK"
                close(forever_channel)
                @test Base.timedwait(() -> isready(forever_stopped), 5) == :ok
                take!(forever_stopped)
            finally
                close(raw_server)
            end
        end

        @testset "security OR, AND, roles, and credential types" begin
            secure_client = C.Client()
            @test_throws ArgumentError call(:secureand; client = secure_client)
            C.credential!(secure_client, "HeaderKey", C.ApiKeyCredential("header"))
            @test_throws ArgumentError call(:secureand; client = secure_client)
            C.credential!(secure_client, "CookieKey", C.ApiKeyCredential("cookie"))
            @test call(:secureand; client = secure_client) == "authorized"
            request = take_request()
            @test captured_header(request, "X-API-Key") == "header"
            @test captured_header(request, "Cookie") == "sid=cookie"

            C.clearcredential!(secure_client, "HeaderKey")
            C.clearcredential!(secure_client, "CookieKey")
            C.credential!(
                secure_client,
                "OAuth",
                C.BearerCredential("token"; scopes = ["wrong"]),
            )
            @test_throws ArgumentError call(:secureor; client = secure_client)
            C.credential!(
                secure_client,
                "OAuth",
                C.BearerCredential("token"; scopes = ["read"]),
            )
            @test call(:secureor; client = secure_client) == "authorized"
            request = take_request()
            @test captured_header(request, "Authorization") == "Bearer token"

            C.clearcredential!(secure_client, "OAuth")
            C.credential!(secure_client, "QueryKey", C.ApiKeyCredential("query"))
            @test call(:secureor; client = secure_client) == "authorized"
            request = take_request()
            @test endswith(request.target, "?access_key=query")

            empty!(secure_client.credentials)
            C.credential!(
                secure_client,
                "Basic",
                C.BasicCredential("user", "password"),
            )
            @test call(:securebasic; client = secure_client) == "authorized"
            request = take_request()
            @test captured_header(request, "Authorization") ==
                  "Basic " * C.Base64.base64encode("user:password")

            empty!(secure_client.credentials)
            C.credential!(
                secure_client,
                "Signature",
                C.HttpCredential("signed"),
            )
            @test call(:securecustom; client = secure_client) == "authorized"
            request = take_request()
            @test captured_header(request, "Authorization") ==
                  "Signature signed"

            empty!(secure_client.credentials)
            C.credential!(
                secure_client,
                "Mutual",
                C.MutualTLSCredential(
                    (; connect_timeout = 2);
                    roles = ["admin"],
                ),
            )
            query = Tuple{String,String,Bool,Bool}[]
            headers = Pair{String,String}[]
            cookies = Tuple{String,String,Bool,Bool}[]
            options = call(
                :_security!,
                secure_client,
                C._OP_securemtls.security,
                query,
                headers,
                cookies,
                NamedTuple(),
            )
            @test options.connect_timeout == 2
        end
    finally
        close(server)
    end
end
