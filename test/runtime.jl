@testset "generated runtime units" begin
    document = OpenAPI.obj(
        "openapi" => "3.2.0",
        "info" => OpenAPI.obj("title" => "Runtime", "version" => "1"),
        "paths" => OpenAPI.obj(
            "/noop" => OpenAPI.obj(
                "get" => OpenAPI.obj(
                    "operationId" => "noop",
                    "responses" => OpenAPI.obj(
                        "204" => OpenAPI.obj("description" => "empty"),
                    ),
                ),
            ),
        ),
    )
    source = OpenAPI.client(document; name = "RuntimeUnitClient")
    host = Module(:RuntimeUnitClientHost)
    Base.include_string(host, source, "RuntimeUnitClient.jl")
    C = Base.invokelatest(getfield, host, :RuntimeUnitClient)

    invoke(function_name, args...; kwargs...) = Base.invokelatest(
        isdefined(C, function_name) ? getfield(C, function_name) :
        getfield(OpenAPI.Runtime, function_name),
        args...;
        kwargs...,
    )

    @testset "generated contract metadata fails closed" begin
        Runtime = OpenAPI.Runtime
        @test_throws UndefKeywordError Runtime.Spec()

        function empty_spec(; security_schemes = Dict{String,NamedTuple}())
            return Runtime.Spec(;
                security_schemes,
                resources = Any[],
                roots = Any[],
                dialects = Any[],
                directional_required = Any[],
                default_server = "",
            )
        end

        descriptor = (
            resource = "https://example.test/missing-schema",
            pointer = "",
        )
        schema_error = try
            invoke(
                :_validate_schema,
                empty_spec(),
                descriptor,
                Dict("wrong" => true),
                "checking malformed generated metadata",
            )
            nothing
        catch error
            error
        end
        @test schema_error isa ArgumentError
        @test occursin("no schema roots", sprint(showerror, schema_error))

        resource = "https://example.test/directional-schema"
        function directional_spec(document, rule)
            return Runtime.Spec(;
                security_schemes = Dict{String,NamedTuple}(),
                resources = Any[(
                    id = resource,
                    retrieval = resource,
                    media_type = "application/schema+json",
                    json = JSON.json(document),
                )],
                roots = Any[(
                    resource = resource,
                    pointer = "",
                    dialect = SchemaEngine.DRAFT202012,
                )],
                dialects = Any[],
                directional_required = Any[rule],
                default_server = "",
            )
        end
        directional_cases = (
            (
                OpenAPI.obj("type" => "object", "required" => Any["x"]),
                (
                    resource = resource * "/missing",
                    pointer = "",
                    input = ("x",),
                    output = (),
                ),
                "missing schema resource",
            ),
            (
                OpenAPI.obj("value" => 1),
                (
                    resource,
                    pointer = "/value",
                    input = ("x",),
                    output = (),
                ),
                "does not resolve to an object",
            ),
            (
                OpenAPI.obj("type" => "object"),
                (
                    resource,
                    pointer = "",
                    input = ("x",),
                    output = (),
                ),
                "has no required array",
            ),
        )
        for (schema, rule, message) in directional_cases
            error = try
                invoke(:_schema_graph, directional_spec(schema, rule), :input)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin(message, sprint(showerror, error))
        end

        broken_scheme = (
            type = :apikey,
            name = "X-Broken-Key",
            location = :bogus,
        )
        client = Runtime.Client(
            empty_spec(;
                security_schemes = Dict{String,NamedTuple}(
                    "BrokenKey" => broken_scheme,
                ),
            );
            credentials = Dict(
                "BrokenKey" => Runtime.ApiKeyCredential("secret"),
            ),
        )
        security_error = try
            invoke(
                :_security!,
                client,
                (((name = "BrokenKey", scopes = ()),),),
                Tuple{String,String,Bool,Bool}[],
                Pair{String,String}[],
                Tuple{String,String,Bool,Bool}[],
                NamedTuple(),
            )
            nothing
        catch error
            error
        end
        @test security_error isa ArgumentError
        @test occursin(
            "unsupported API key location :bogus",
            sprint(showerror, security_error),
        )
    end

    @testset "path styles" begin
        @test invoke(:_path_parameter, "id", ["a", "b"], :simple, false) == "a,b"
        @test invoke(
            :_path_parameter,
            "id",
            Dict("role" => "admin", "first" => "Alex"),
            :simple,
            true,
        ) in ("role=admin,first=Alex", "first=Alex,role=admin")
        @test invoke(:_path_parameter, "id", ["a", "b"], :label, true) == ".a.b"
        @test invoke(:_path_parameter, "id", ["a", "b"], :matrix, true) ==
              ";id=a;id=b"
        @test invoke(:_path_parameter, "id", nothing, :matrix, false) == ";id"
        @test invoke(:_path_parameter, "id", "a/b", :simple, false) == "a%2Fb"
    end

    @testset "date-time decoding accepts RFC 3339 and zone-less ISO 8601" begin
        decode(value) = invoke(:_decode, Dates.DateTime, value)
        # canonical RFC 3339 forms
        @test decode("2026-08-07T15:00:00Z") == Dates.DateTime(2026, 8, 7, 15)
        @test decode("2026-08-07T15:00:00.076Z") ==
              Dates.DateTime(2026, 8, 7, 15, 0, 0, 76)
        @test decode("2026-08-07T15:00:00+02:00") ==
              Dates.DateTime(2026, 8, 7, 13)
        @test decode("2026-08-07T15:00:00-04:30") ==
              Dates.DateTime(2026, 8, 7, 19, 30)
        # zone-less ISO 8601, as most JSON serializers print naive
        # timestamps: interpreted as UTC, mirroring _encode's convention
        @test decode("2026-08-07T15:00:00") == Dates.DateTime(2026, 8, 7, 15)
        @test decode("2026-08-07T15:00:00.076") ==
              Dates.DateTime(2026, 8, 7, 15, 0, 0, 76)
        # still not anything-goes
        DecodeError = Base.invokelatest(getfield, C, :DecodeError)
        @test_throws DecodeError decode("2026-08-07")
        @test_throws DecodeError decode("2026-08-07T15:00:00+02")
        @test_throws DecodeError decode("garbage")
    end

    @testset "datetime = :zoned preserves time zone offsets" begin
        zoned_document = OpenAPI.obj(
            "openapi" => "3.2.0",
            "info" => OpenAPI.obj("title" => "Zoned", "version" => "1"),
            "paths" => OpenAPI.obj(
                "/event" => OpenAPI.obj(
                    "get" => OpenAPI.obj(
                        "operationId" => "getEvent",
                        "responses" => OpenAPI.obj(
                            "200" => OpenAPI.obj(
                                "description" => "event",
                                "content" => OpenAPI.obj(
                                    "application/json" => OpenAPI.obj(
                                        "schema" => OpenAPI.obj(
                                            "\$ref" => "#/components/schemas/Event",
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
                    "Event" => OpenAPI.obj(
                        "type" => "object",
                        "required" => ["at"],
                        "properties" => OpenAPI.obj(
                            "at" => OpenAPI.obj(
                                "type" => "string",
                                "format" => "date-time",
                            ),
                        ),
                        "additionalProperties" => false,
                    ),
                ),
            ),
        )
        @test_throws ArgumentError OpenAPI.client(
            zoned_document;
            name = "ZonedUnitClient",
            datetime = :bogus,
        )
        source = OpenAPI.client(
            zoned_document;
            name = "ZonedUnitClient",
            datetime = :zoned,
        )
        @test occursin("using TimeZones", source)
        @test occursin("at::TimeZones.ZonedDateTime", source)
        zoned_host = Module(:ZonedUnitClientHost)
        Base.include_string(zoned_host, source, "ZonedUnitClient.jl")
        Cz = Base.invokelatest(getfield, zoned_host, :ZonedUnitClient)
        zoned_invoke(function_name, args...; kwargs...) =
            Base.invokelatest(getfield(Cz, function_name), args...; kwargs...)

        decoded = zoned_invoke(
            :_decode,
            TimeZones.ZonedDateTime,
            "2026-08-07T15:00:00.5+05:30",
        )
        @test decoded == TimeZones.ZonedDateTime(
            Dates.DateTime(2026, 8, 7, 15, 0, 0, 500),
            TimeZones.tz"UTC+05:30",
        )
        @test Dates.value(decoded.zone.offset) == 5 * 3600 + 30 * 60
        encoded = zoned_invoke(:_encode, decoded)
        @test encoded == "2026-08-07T15:00:00.500+05:30"
        @test zoned_invoke(:_decode, TimeZones.ZonedDateTime, encoded) == decoded
        @test zoned_invoke(:_decode, TimeZones.ZonedDateTime, "2026-08-07T15:00:00Z") ==
              TimeZones.ZonedDateTime(
            Dates.DateTime(2026, 8, 7, 15),
            TimeZones.tz"UTC",
        )
        @test zoned_invoke(:_decode, TimeZones.ZonedDateTime, "2026-08-07T15:00:00") ==
              TimeZones.ZonedDateTime(
            Dates.DateTime(2026, 8, 7, 15),
            TimeZones.tz"UTC",
        )
        ZonedDecodeError = Base.invokelatest(getfield, Cz, :DecodeError)
        @test_throws ZonedDecodeError zoned_invoke(
            :_decode,
            TimeZones.ZonedDateTime,
            "2026-08-07T15:00:00+02",
        )

        event = zoned_invoke(
            :_decode,
            Base.invokelatest(getfield, Cz, :EventModel),
            JSON.parse("""{"at":"2026-08-07T15:00:00-04:00"}"""),
        )
        @test Dates.value(event.at.zone.offset) == -4 * 3600
        @test zoned_invoke(:_encode, event)["at"] == "2026-08-07T15:00:00.000-04:00"

        # the default mapping stays plain, trim-friendly Dates.DateTime
        default_source = OpenAPI.client(zoned_document; name = "ZonedUnitClient")
        @test !occursin("ZonedDateTime", default_source)
        @test occursin("at::Dates.DateTime", default_source)
    end

    @testset "query, header, and cookie styles" begin
        @test invoke(:_query_parameter, "q", ["a", "b"], :form, false, false) ==
              [("q", "a,b", true)]
        @test invoke(:_query_parameter, "q", ["a", "b"], :form, true, false) ==
              [("q", "a", false), ("q", "b", false)]
        @test invoke(
            :_query_parameter,
            "q",
            ["a", "b"],
            :spaceDelimited,
            false,
            false,
        ) == [("q", "a b", false)]
        @test invoke(
            :_query_parameter,
            "q",
            ["a", "b"],
            :pipeDelimited,
            false,
            false,
        ) == [("q", "a|b", false)]
        deep = invoke(
            :_query_parameter,
            "filter",
            Dict("role" => "admin"),
            :deepObject,
            true,
            false,
        )
        @test deep == [("filter[role]", "admin", false)]
        @test invoke(
            :_query_parameter,
            "expand",
            ["customer", "invoice"],
            :deepObject,
            true,
            false,
        ) == [
            ("expand[]", "customer", false),
            ("expand[]", "invoice", false),
        ]
        @test invoke(:_query_parameter, "created", 7, :deepObject, true, false) ==
              [("created", "7", false)]
        @test_throws ArgumentError invoke(
            :_query_parameter,
            "filter",
            Dict("nested" => Dict("x" => 1)),
            :deepObject,
            true,
            false,
        )

        @test invoke(:_header_parameter, ["a", "b"], false) == "a,b"
        malformed_header = (
            location = :header,
            style = :bogus,
            explode = false,
            content = (),
            name = "X-Test",
        )
        @test_throws ArgumentError invoke(
            :_append_parameter!,
            C.DEFAULT_CLIENT,
            "/",
            Tuple{String,String,Bool,Bool}[],
            Pair{String,String}[],
            Tuple{String,String,Bool,Bool}[],
            malformed_header,
            "value",
        )
        @test invoke(:_cookie_parameter, "id", ["a", "b"], :form, true, false) ==
              [("id=a&id=b", "", true, true)]
        @test invoke(:_cookie_parameter, "id", ["a", "b"], :cookie, false, false) ==
              [("id", "a,b", true, false)]
    end

    @testset "form defaults use content-based serialization" begin
        pairs = invoke(
            :_form_pairs,
            C.DEFAULT_CLIENT,
            Dict(
                "address" => Dict("city" => "Salt Lake City"),
                "items" => [Dict("id" => 1), Dict("id" => 2)],
            ),
            (),
        )
        @test ("address", "{\"city\":\"Salt Lake City\"}", false, false) in pairs
        @test count(pair -> pair[1] == "items", pairs) == 2
        @test ("items", "{\"id\":1}", false, false) in pairs
        @test ("items", "{\"id\":2}", false, false) in pairs
    end

    @testset "URI and header safety" begin
        reserved = ":/?#[]@!\$&'()*+,;="
        @test invoke(:_escape, reserved; allow_reserved = true) == reserved
        @test invoke(:_escape, "%2F"; allow_reserved = true) == "%2F"
        @test invoke(:_escape, "a b") == "a%20b"
        @test invoke(:_safe_header, "X-Test", "ok") == ("X-Test" => "ok")
        @test_throws ArgumentError invoke(:_safe_header, "Bad Header", "ok")
        @test_throws ArgumentError invoke(:_safe_header, "X-Test", "ok\r\nInjected: x")
    end

    @testset "media and response selection" begin
        @test invoke(:_media_match_score, "application/problem+json", "application/*+json") ==
              3
        @test invoke(:_media_match_score, "text/plain", "text/*") == 2
        @test invoke(:_media_match_score, "application/json", "*/*") == 1
        @test invoke(:_media_match_score, "application/json", "text/*") == 0
        @test invoke(
            :_media_match,
            "application/json; stream=watch",
            "application/json;stream=watch",
        )
        @test !invoke(
            :_media_match,
            "application/json",
            "application/json;stream=watch",
        )
        @test invoke(
            :_media_match,
            "application/json; charset=UTF-8",
            "application/json;charset=utf-8",
        )

        plain = (media_type = "application/json", value = :plain)
        watch = (media_type = "application/json;stream=watch", value = :watch)
        @test invoke(
            :_select_media,
            (plain, watch),
            "application/json; stream=watch",
        ) == watch
        @test invoke(
            :_select_media,
            (watch, plain),
            "application/json",
        ) == plain
        quoted = (
            media_type = "application/json;profile=\"a;b\"",
            value = :quoted,
        )
        @test invoke(
            :_select_media,
            (plain, quoted),
            "application/json; profile=\"a;b\"",
        ) == quoted

        responses = (
            (selector = "default", media = (), headers = ()),
            (selector = "2XX", media = (), headers = ()),
            (selector = "201", media = (), headers = ()),
        )
        @test invoke(:_select_response, responses, 201).selector == "201"
        @test invoke(:_select_response, responses, 202).selector == "2XX"
        @test invoke(:_select_response, responses, 404).selector == "default"
    end

    @testset "Set-Cookie response headers stay line-separated" begin
        headers = [
            "Set-Cookie" => "lang=en-US; Expires=Wed, 09 Jun 2021 10:18:14 GMT",
            "Set-Cookie" => "foo=bar; Expires=Wed, 09 Jun 2021 10:18:14 GMT",
        ]
        schema_descriptor = (
            headers = (
                (
                    name = "Set-Cookie",
                    type = Dict{String,String},
                    required = true,
                    shape = :object,
                    explode = true,
                    schema = nothing,
                    content = (),
                ),
            ),
        )
        decoded = invoke(
            :_decode_response_headers,
            C.DEFAULT_CLIENT,
            schema_descriptor,
            headers,
        )
        @test decoded["Set-Cookie"]["lang"] ==
              "en-US; Expires=Wed, 09 Jun 2021 10:18:14 GMT"
        @test decoded["Set-Cookie"]["foo"] ==
              "bar; Expires=Wed, 09 Jun 2021 10:18:14 GMT"

        header = only(schema_descriptor.headers)
        for changed in ((shape = :bogus,), (explode = :bogus,))
            malformed = (headers = (merge(header, changed),),)
            @test_throws ArgumentError invoke(
                :_decode_response_headers,
                C.DEFAULT_CLIENT,
                malformed,
                headers,
            )
        end

        content_descriptor = (
            headers = (
                (
                    name = "Set-Cookie",
                    type = String,
                    required = true,
                    shape = :scalar,
                    explode = false,
                    schema = nothing,
                    content = ((
                        media_type = "text/plain",
                        type = String,
                        schema = nothing,
                        encodings = (),
                        fields = (),
                    ),),
                ),
            ),
        )
        content = invoke(
            :_decode_response_headers,
            C.DEFAULT_CLIENT,
            content_descriptor,
            headers,
        )
        @test content["Set-Cookie"] == join(last.(headers), '\n')
    end

    @testset "strict and binary-safe decoding" begin
        @test_throws C.DecodeError invoke(
            :_parse_json,
            Vector{UInt8}([0xff]),
            "testing",
        )
        @test_throws C.DecodeError invoke(
            :_parse_json,
            "{\"x\":1,\"x\":2}",
            "testing",
        )
        @test_throws C.DecodeError invoke(
            :_decode_body,
            C.DEFAULT_CLIENT,
            String,
            "text/plain",
            UInt8[0xff],
            nothing,
        )

        error = C.ApiError(
            "noop",
            500,
            Pair{String,String}[],
            Dict{String,Any}(),
            UInt8[0xff, 0x00],
            nothing,
            nothing,
        )
        shown = sprint(showerror, error)
        @test occursin("2 binary bytes", shown)
        @test occursin("ff00", shown)
    end
end
