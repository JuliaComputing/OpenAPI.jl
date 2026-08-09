function server_parameter(name, location, schema; kwargs...)
    entries = Any["name" => name, "in" => location, "schema" => schema]
    for (key, value) in kwargs
        push!(entries, replace(String(key), "_" => "") => value)
    end
    return OpenAPI.obj(entries...)
end

const SERVER_ROUNDTRIP_DOCUMENT = OpenAPI.obj(
    "openapi" => "3.1.0",
    "info" => OpenAPI.obj("title" => "Server Round Trip", "version" => "1.0.0"),
    "paths" => OpenAPI.obj(
        "/styles/{simple}/{label}/{matrix}/{mexp}" => OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "styles",
                "parameters" => Any[
                    server_parameter(
                        "simple",
                        "path",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string"));
                        required = true,
                    ),
                    server_parameter(
                        "label",
                        "path",
                        OpenAPI.obj("type" => "string");
                        required = true,
                        style = "label",
                    ),
                    server_parameter(
                        "matrix",
                        "path",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "integer"));
                        required = true,
                        style = "matrix",
                    ),
                    server_parameter(
                        "mexp",
                        "path",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "integer"));
                        required = true,
                        style = "matrix",
                        explode = true,
                    ),
                    server_parameter(
                        "qform",
                        "query",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string"));
                        required = true,
                        explode = false,
                    ),
                    server_parameter(
                        "qexp",
                        "query",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string")),
                    ),
                    server_parameter(
                        "spaces",
                        "query",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string"));
                        style = "spaceDelimited",
                        explode = false,
                    ),
                    server_parameter(
                        "pipes",
                        "query",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string"));
                        style = "pipeDelimited",
                        explode = false,
                    ),
                    server_parameter(
                        "deep",
                        "query",
                        OpenAPI.obj(
                            "type" => "object",
                            "properties" => OpenAPI.obj(
                                "a" => OpenAPI.obj("type" => "string"),
                                "b" => OpenAPI.obj("type" => "integer"),
                            ),
                        );
                        style = "deepObject",
                        explode = true,
                    ),
                    server_parameter(
                        "obj",
                        "query",
                        OpenAPI.obj(
                            "type" => "object",
                            "properties" => OpenAPI.obj(
                                "x" => OpenAPI.obj("type" => "string"),
                                "y" => OpenAPI.obj("type" => "integer"),
                            ),
                        );
                        explode = true,
                    ),
                    server_parameter(
                        "X-Items",
                        "header",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "integer")),
                    ),
                    server_parameter("sess", "cookie", OpenAPI.obj("type" => "string")),
                    server_parameter(
                        "csv",
                        "cookie",
                        OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string"));
                        explode = false,
                    ),
                ],
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj(
                        "description" => "echo",
                        "content" => OpenAPI.obj(
                            "application/json" => OpenAPI.obj(
                                "schema" => OpenAPI.obj("\$ref" => "#/components/schemas/StylesEcho"),
                            ),
                        ),
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
                            "schema" => OpenAPI.obj(
                                "type" => "object",
                                "required" => Any["q", "meta"],
                                "properties" => OpenAPI.obj(
                                    "q" => OpenAPI.obj("type" => "string"),
                                    "limit" => OpenAPI.obj("type" => "integer"),
                                    "tags" => OpenAPI.obj(
                                        "type" => "array",
                                        "items" => OpenAPI.obj("type" => "string"),
                                    ),
                                    "meta" => OpenAPI.obj(
                                        "type" => "object",
                                        "required" => Any["code"],
                                        "properties" => OpenAPI.obj(
                                            "code" => OpenAPI.obj("type" => "string"),
                                        ),
                                        "additionalProperties" => false,
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj(
                        "description" => "echo",
                        "content" => OpenAPI.obj(
                            "application/json" => OpenAPI.obj(
                                "schema" => OpenAPI.obj(
                                    "type" => "object",
                                    "properties" => OpenAPI.obj(
                                        "q" => OpenAPI.obj("type" => "string"),
                                        "limit" => OpenAPI.obj("type" => "integer"),
                                        "tags" => OpenAPI.obj(
                                            "type" => "array",
                                            "items" => OpenAPI.obj("type" => "string"),
                                        ),
                                        "meta" => OpenAPI.obj(
                                            "type" => "object",
                                            "required" => Any["code"],
                                            "properties" => OpenAPI.obj(
                                                "code" => OpenAPI.obj("type" => "string"),
                                            ),
                                            "additionalProperties" => false,
                                        ),
                                        "raw" => OpenAPI.obj("type" => "string"),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        ),
        "/upload" => OpenAPI.obj(
            "post" => OpenAPI.obj(
                "operationId" => "upload",
                "requestBody" => OpenAPI.obj(
                    "required" => true,
                    "content" => OpenAPI.obj(
                        "multipart/form-data" => OpenAPI.obj(
                            "schema" => OpenAPI.obj(
                                "type" => "object",
                                "required" => Any["note", "file", "count"],
                                "properties" => OpenAPI.obj(
                                    "note" => OpenAPI.obj("type" => "string"),
                                    "file" => OpenAPI.obj(
                                        "type" => "string",
                                        "format" => "binary",
                                    ),
                                    "count" => OpenAPI.obj("type" => "integer"),
                                ),
                            ),
                        ),
                    ),
                ),
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj(
                        "description" => "echo",
                        "content" => OpenAPI.obj(
                            "application/json" => OpenAPI.obj(
                                "schema" => OpenAPI.obj(
                                    "type" => "object",
                                    "properties" => OpenAPI.obj(
                                        "note" => OpenAPI.obj("type" => "string"),
                                        "bytes" => OpenAPI.obj("type" => "integer"),
                                        "count" => OpenAPI.obj("type" => "integer"),
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        ),
        "/text" => OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "textOut",
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj(
                        "description" => "text",
                        "content" => OpenAPI.obj(
                            "text/plain" => OpenAPI.obj(
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ),
                    ),
                ),
            ),
        ),
        "/bin" => OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "binOut",
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj(
                        "description" => "bytes",
                        "content" => OpenAPI.obj(
                            "application/octet-stream" => OpenAPI.obj(
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ),
                    ),
                ),
            ),
        ),
        "/custom" => OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "custom",
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj(
                        "description" => "text",
                        "content" => OpenAPI.obj(
                            "text/plain" => OpenAPI.obj(
                                "schema" => OpenAPI.obj("type" => "string"),
                            ),
                        ),
                    ),
                ),
            ),
        ),
        "/nothing" => OpenAPI.obj(
            "put" => OpenAPI.obj(
                "operationId" => "noContent",
                "responses" => OpenAPI.obj(
                    "204" => OpenAPI.obj("description" => "empty"),
                ),
            ),
        ),
        "/empty-200" => OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "empty200",
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj("description" => "empty success"),
                ),
            ),
        ),
        "/null" => OpenAPI.obj(
            "get" => OpenAPI.obj(
                "operationId" => "nullOut",
                "responses" => OpenAPI.obj(
                    "200" => OpenAPI.obj(
                        "description" => "nullable success",
                        "content" => OpenAPI.obj(
                            "application/json" => OpenAPI.obj(
                                "schema" => OpenAPI.obj(
                                    "type" => Any["string", "null"],
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
            "StylesEcho" => OpenAPI.obj(
                "type" => "object",
                "properties" => OpenAPI.obj(
                    "simple" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string")),
                    "label" => OpenAPI.obj("type" => "string"),
                    "matrix" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "integer")),
                    "mexp" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "integer")),
                    "qform" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string")),
                    "qexp" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string")),
                    "spaces" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string")),
                    "pipes" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string")),
                    "deep" => OpenAPI.obj(
                        "type" => "object",
                        "properties" => OpenAPI.obj(
                            "a" => OpenAPI.obj("type" => "string"),
                            "b" => OpenAPI.obj("type" => "integer"),
                        ),
                    ),
                    "obj" => OpenAPI.obj(
                        "type" => "object",
                        "properties" => OpenAPI.obj(
                            "x" => OpenAPI.obj("type" => "string"),
                            "y" => OpenAPI.obj("type" => "integer"),
                        ),
                    ),
                    "items" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "integer")),
                    "sess" => OpenAPI.obj("type" => "string"),
                    "csv" => OpenAPI.obj("type" => "array", "items" => OpenAPI.obj("type" => "string")),
                ),
            ),
        ),
    ),
)

const SERVER_IMPL_SOURCE = """
using HTTP

function styles(
    req,
    simple,
    label,
    matrix,
    mexp;
    qform,
    qexp = String[],
    spaces = String[],
    pipes = String[],
    deep = nothing,
    obj = nothing,
    x_items = Int[],
    sess = "",
    csv = String[],
)
    return (;
        simple,
        label,
        matrix,
        mexp,
        qform,
        qexp,
        spaces,
        pipes,
        deep = something(deep, (;)),
        obj = something(obj, (;)),
        items = x_items,
        sess,
        csv,
    )
end

submitform(req, body) = (;
    q = body.q,
    limit = body.limit isa Int ? body.limit : 0,
    tags = body.tags isa Vector ? body.tags : String[],
    meta = body.meta,
    raw = String(copy(req.body)),
)

upload(req, body) = (;
    note = body.note,
    bytes = length(body.file),
    count = body.count,
)

textout(req) = "plain text"

binout(req) = Vector{UInt8}(codeunits("raw-bytes"))

custom(req) = HTTP.Response(418, ["Content-Type" => "text/plain"], "teapot")

nocontent(req) = nothing

empty200(req) = nothing

nullout(req) = nothing
"""

@testset "server generation" begin
    server_source = OpenAPI.server(SERVER_ROUNDTRIP_DOCUMENT; name = "RoundTripServer")
    @test server_source == OpenAPI.server(SERVER_ROUNDTRIP_DOCUMENT; name = "RoundTripServer")
    @test startswith(server_source, "# Generated by OpenAPI.jl")
    @test occursin("register!", server_source)
    @test occursin(
        "styles(request, simple::Vector{String}, label::String, matrix::Vector{Int64}, mexp::Vector{Int64};",
        server_source,
    )

    server_host = Module(:ServerGenHost)
    Base.include_string(server_host, server_source, "RoundTripServer.jl")
    S = Base.invokelatest(getfield, server_host, :RoundTripServer)
    sregister(args...; kwargs...) =
        Base.invokelatest(getfield(S, :register!), args...; kwargs...)

    impl = Module(:ServerGenImpl)
    Base.include_string(impl, SERVER_IMPL_SOURCE, "ServerGenImpl.jl")

    @testset "missing implementations are reported" begin
        empty_impl = Module(:ServerGenEmptyImpl)
        router = HTTP.Router()
        error = try
            sregister(router, empty_impl)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin("missing handler functions", error.msg)
        @test occursin("styles(request", error.msg)
    end

    @test Base.invokelatest(getfield, S, :register) ===
          Base.invokelatest(getfield, S, :register!)

    middleware_hits = Ref(0)
    middleware = handler -> function (request)
        middleware_hits[] += 1
        return handler(request)
    end
    router = HTTP.Router()
    sregister(router, impl; middleware)
    prefixed = HTTP.Router()
    sregister(prefixed, impl; path_prefix = "/v3")

    server = HTTP.serve!(router, "127.0.0.1", 0; verbose = false)
    prefixed_server = HTTP.serve!(prefixed, "127.0.0.1", 0; verbose = false)
    try
        port = HTTP.port(server)
        base = "http://127.0.0.1:$port"

        client_source = OpenAPI.client(SERVER_ROUNDTRIP_DOCUMENT; name = "RoundTripClient")
        client_host = Module(:ServerGenClientHost)
        Base.include_string(client_host, client_source, "RoundTripClient.jl")
        C = Base.invokelatest(getfield, client_host, :RoundTripClient)
        call(name, args...; kwargs...) =
            Base.invokelatest(getfield(C, name), args...; kwargs...)
        call(:server!, base)

        @testset "parameter style round trip" begin
            echo = call(
                :styles,
                ["a", "b/slash"],
                "labelled",
                [1, 2],
                [3, 4];
                qform = ["q1", "q,2"],
                qexp = ["e1", "e2"],
                spaces = ["s1", "s2"],
                pipes = ["p1", "p2"],
                deep = call(:StylesDeep, "deep", 7, Dict{String,Any}()),
                obj = call(:StylesObj, "ex", 9, Dict{String,Any}()),
                x_items = [10, 11],
                sess = "session-1",
                csv = ["c1", "c2"],
            )
            @test echo.simple == ["a", "b/slash"]
            @test echo.label == "labelled"
            @test echo.matrix == [1, 2]
            @test echo.mexp == [3, 4]
            @test echo.qform == ["q1", "q,2"]
            @test echo.qexp == ["e1", "e2"]
            @test echo.spaces == ["s1", "s2"]
            @test echo.pipes == ["p1", "p2"]
            @test echo.deep.a == "deep"
            @test echo.deep.b == 7
            @test echo.obj.x == "ex"
            @test echo.obj.y == 9
            @test echo.items == [10, 11]
            @test echo.sess == "session-1"
            @test echo.csv == ["c1", "c2"]
            @test middleware_hits[] == 1
        end

        @testset "form and multipart bodies round trip" begin
            meta = call(:SubmitformRequestMetaModel; code = "001")
            form_body = call(
                :SubmitformRequest;
                q = "001",
                limit = 5,
                tags = ["solo"],
                meta,
            )
            form_echo = call(:submitform, form_body)
            @test form_echo.q == "001"
            @test form_echo.limit == 5
            @test form_echo.tags == ["solo"]
            @test form_echo.meta.code == "001"
            @test !isempty(form_echo.raw)
            @test occursin("q=001", form_echo.raw)

            bytes = Vector{UInt8}(codeunits("valid UTF-8 binary"))
            upload_body = call(
                :UploadModelRequest;
                note = "note text",
                file = bytes,
                count = 7,
            )
            upload_echo = call(:upload, upload_body)
            @test upload_echo.note == "note text"
            @test upload_echo.bytes == length(bytes)
            @test upload_echo.count == 7
        end

        @testset "response encodings" begin
            @test call(:textout) == "plain text"
            @test call(:binout) == "raw-bytes"
            @test call(:nocontent) === nothing
            empty = call(:empty200; with_http_info = true)
            @test empty.status == 200
            @test empty.body === nothing
            nullable = call(:nullout; with_http_info = true)
            @test nullable.status == 200
            @test nullable.body === nothing
        end

        @testset "framework response passthrough" begin
            response = HTTP.get("$base/custom"; status_exception = false)
            @test response.status == 418
            @test String(response.body) == "teapot"
        end

        @testset "request error responses" begin
            RequestFailure = Base.invokelatest(getfield, S, :_RequestFailure)
            @test_throws RequestFailure Base.invokelatest(
                getfield(S, :_percent_decode),
                "%ZZ",
            )
            @test_throws RequestFailure Base.invokelatest(
                getfield(S, :_percent_decode),
                "%",
            )

            unicode = HTTP.get(
                "$base/styles/a/.l/;matrix=1/;mexp=1?qform=x&deep[%C3%A9]=value";
                status_exception = false,
            )
            @test unicode.status == 200
            unicode_echo = JSON.parse(unicode.body)
            @test unicode_echo["deep"]["é"] == "value"

            bad_path = HTTP.get(
                "$base/styles/a/.l/;matrix=oops/;mexp=1?qform=x";
                status_exception = false,
            )
            @test bad_path.status == 400
            @test occursin("matrix", String(bad_path.body))

            missing_required = HTTP.get(
                "$base/styles/a/.l/;matrix=1/;mexp=1";
                status_exception = false,
            )
            @test missing_required.status == 400
            @test occursin("qform", String(missing_required.body))

            invalid_body = HTTP.post(
                "$base/form";
                headers = ["Content-Type" => "application/json"],
                body = "{}",
                status_exception = false,
            )
            @test invalid_body.status == 415

            unknown_route = HTTP.get("$base/absent"; status_exception = false)
            @test unknown_route.status == 404
        end

        @testset "path prefix" begin
            prefixed_port = HTTP.port(prefixed_server)
            response = HTTP.get(
                "http://127.0.0.1:$prefixed_port/v3/text";
                status_exception = false,
            )
            @test response.status == 200
            @test String(response.body) == "plain text"
            unprefixed = HTTP.get(
                "http://127.0.0.1:$prefixed_port/text";
                status_exception = false,
            )
            @test unprefixed.status == 404
        end
    finally
        close(server)
        close(prefixed_server)
    end
end

@testset "server planning gates" begin
    @testset "framework selection" begin
        plan = OpenAPI.serverplan(SERVER_ROUNDTRIP_DOCUMENT; name = "GateServer")
        @test OpenAPI.server(plan; framework = "HTTP") isa String
        error = try
            OpenAPI.server(plan; framework = :Nope)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin("HTTP", error.msg)
    end

    @testset "multipart/mixed requests are rejected" begin
        document = OpenAPI.obj(
            "openapi" => "3.1.0",
            "info" => OpenAPI.obj("title" => "Mixed", "version" => "1.0.0"),
            "paths" => OpenAPI.obj(
                "/mixed" => OpenAPI.obj(
                    "post" => OpenAPI.obj(
                        "operationId" => "mixed",
                        "requestBody" => OpenAPI.obj(
                            "content" => OpenAPI.obj(
                                "multipart/mixed" => OpenAPI.obj(
                                    "schema" => OpenAPI.obj("type" => "object"),
                                ),
                            ),
                        ),
                        "responses" => OpenAPI.obj(
                            "204" => OpenAPI.obj("description" => "empty"),
                        ),
                    ),
                ),
            ),
        )
        error = try
            OpenAPI.serverplan(document)
            nothing
        catch caught
            caught
        end
        @test error isa OpenAPI.OpenAPIError
        @test any(
            diagnostic -> diagnostic.code === :unsupported_multipart_server_generation,
            error.diagnostics,
        )
        @test OpenAPI.plan(document) isa OpenAPI.ClientPlan
    end

    @testset "lossy request-body encodings are rejected" begin
        function body_encoding_document(schema, encoding)
            return OpenAPI.obj(
                "openapi" => "3.2.0",
                "info" => OpenAPI.obj("title" => "Encoding", "version" => "1.0.0"),
                "paths" => OpenAPI.obj(
                    "/encoded" => OpenAPI.obj(
                        "post" => OpenAPI.obj(
                            "operationId" => "encoded",
                            "requestBody" => OpenAPI.obj(
                                "content" => OpenAPI.obj(
                                    "multipart/form-data" => OpenAPI.obj(
                                        "schema" => schema,
                                        "encoding" => encoding,
                                    ),
                                ),
                            ),
                            "responses" => OpenAPI.obj(
                                "204" => OpenAPI.obj("description" => "empty"),
                            ),
                        ),
                    ),
                ),
            )
        end

        nested = body_encoding_document(
            OpenAPI.obj(
                "type" => "object",
                "properties" => OpenAPI.obj(
                    "bundle" => OpenAPI.obj(
                        "type" => "object",
                        "properties" => OpenAPI.obj(
                            "child" => OpenAPI.obj("type" => "string"),
                        ),
                    ),
                ),
            ),
            OpenAPI.obj(
                "bundle" => OpenAPI.obj(
                    "contentType" => "multipart/form-data",
                    "encoding" => OpenAPI.obj(
                        "child" => OpenAPI.obj("contentType" => "text/plain"),
                    ),
                ),
            ),
        )
        headers = body_encoding_document(
            OpenAPI.obj(
                "type" => "object",
                "properties" => OpenAPI.obj(
                    "file" => OpenAPI.obj("type" => "string", "format" => "binary"),
                ),
            ),
            OpenAPI.obj(
                "file" => OpenAPI.obj(
                    "headers" => OpenAPI.obj(
                        "X-Part" => OpenAPI.obj(
                            "schema" => OpenAPI.obj("type" => "string"),
                        ),
                    ),
                ),
            ),
        )
        styled = body_encoding_document(
            OpenAPI.obj(
                "type" => "object",
                "properties" => OpenAPI.obj(
                    "items" => OpenAPI.obj(
                        "type" => "array",
                        "items" => OpenAPI.obj("type" => "string"),
                    ),
                ),
            ),
            OpenAPI.obj(
                "items" => OpenAPI.obj("style" => "form", "explode" => false),
            ),
        )

        for (document, code) in (
            (nested, :unsupported_nested_server_encoding),
            (headers, :unsupported_multipart_server_headers),
            (styled, :unsupported_server_encoding_style),
        )
            error = @test_throws OpenAPI.OpenAPIError OpenAPI.serverplan(document)
            @test code in Set(diagnostic.code for diagnostic in error.value.diagnostics)
            @test OpenAPI.plan(document) isa OpenAPI.ClientPlan
        end
    end

    @testset "ambiguous exploded object parameters are rejected" begin
        exploded(name) = OpenAPI.obj(
            "name" => name,
            "in" => "query",
            "style" => "form",
            "explode" => true,
            "schema" => OpenAPI.obj(
                "type" => "object",
                "properties" => OpenAPI.obj("k" => OpenAPI.obj("type" => "string")),
            ),
        )
        document = OpenAPI.obj(
            "openapi" => "3.1.0",
            "info" => OpenAPI.obj("title" => "Ambiguous", "version" => "1.0.0"),
            "paths" => OpenAPI.obj(
                "/search" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "search",
                        "parameters" => Any[exploded("first"), exploded("second")],
                        "responses" => OpenAPI.obj(
                            "204" => OpenAPI.obj("description" => "empty"),
                        ),
                    ),
                ),
            ),
        )
        error = try
            OpenAPI.serverplan(document)
            nothing
        catch caught
            caught
        end
        @test error isa OpenAPI.OpenAPIError
        @test any(
            diagnostic -> diagnostic.code === :ambiguous_exploded_object_parameters,
            error.diagnostics,
        )
        @test OpenAPI.plan(document) isa OpenAPI.ClientPlan
    end
end
