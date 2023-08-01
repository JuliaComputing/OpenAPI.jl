using OpenAPI
using OpenAPI.Clients
using Test
using Dates
using TimeZones
using Base64
using Downloads

function test_date()
    dt_now = now()
    dt_string = string(ZonedDateTime(dt_now, localzone()))
    dt = OpenAPI.str2zoneddatetime(convert(Vector{UInt8}, codeunits(dt_string)))
    @test dt == OpenAPI.str2zoneddatetime(dt_now)
    @test dt_string == string(dt)

    dt_string = string(dt_now)
    dt = OpenAPI.str2datetime(convert(Vector{UInt8}, codeunits(dt_string)))
    @test dt == OpenAPI.str2datetime(dt_now)
    @test dt_string == string(dt)

    dt_string = string(Date(dt_now))
    dt = OpenAPI.str2date(convert(Vector{UInt8}, codeunits(dt_string)))
    @test dt == OpenAPI.str2date(Date(dt_now))
    @test dt_string == string(dt)

    dates = ["2017-11-14", "2020-01-01"]
    timesep = [" ", "T"]
    times =
        ["11:03:53", "11:03:53.12", "11:03:53.123", "11:03:53.123456", "11:03:53.123456789"]
    timezones = ["", "+10:00", "-10:00", "Z"]

    for date in dates
        d = OpenAPI.str2date(date)
        for sep in timesep
            for time in times
                reduced_time = length(time) > 12 ? SubString(time, 1, 12) : time
                t = Time(reduced_time)
                for tz in timezones
                    dt_string = date * sep * time * tz
                    reduced_dt_string = date * sep * reduced_time * tz
                    @test OpenAPI.reduce_to_ms_precision(dt_string) == reduced_dt_string
                    zdt = OpenAPI.str2zoneddatetime(convert(Vector{UInt8}, codeunits(dt_string)))
                    dt = OpenAPI.str2datetime(convert(Vector{UInt8}, codeunits(dt_string)))
                    @test d == Date(zdt)
                    @test d == Date(dt)
                    @test t == Time(zdt)
                    @test t == Time(dt)
                end
            end
        end
    end

    for tz in timezones
        @test OpenAPI.str2date("2017-11-14"*tz) == Date(2017, 11, 14)
    end
end

function as_taskfailedexception(ex)
    try
        task = @async throw(ex)
        wait(task)
    catch ex
        return ex
    end
end

function test_longpoll_exception_check()
    resp = OpenAPI.Clients.Downloads.Response("http", "http://localhost", 200, "no error", [])
    reqerr1 = OpenAPI.Clients.Downloads.RequestError("http://localhost", 500, "not timeout error", resp)
    reqerr2 = OpenAPI.Clients.Downloads.RequestError("http://localhost", 200, "Operation timed out after 300 milliseconds with 0 bytes received", resp) # timeout error

    @test OpenAPI.Clients.is_longpoll_timeout("not an exception") == false

    openapiex1 = OpenAPI.Clients.ApiException(reqerr1)
    @test OpenAPI.Clients.is_longpoll_timeout(openapiex1) == false
    @test OpenAPI.Clients.is_longpoll_timeout(as_taskfailedexception(openapiex1)) == false

    openapiex2 = OpenAPI.Clients.ApiException(reqerr2)
    @test OpenAPI.Clients.is_longpoll_timeout(openapiex2)
    @test OpenAPI.Clients.is_longpoll_timeout(as_taskfailedexception(openapiex2))

    @test OpenAPI.Clients.is_longpoll_timeout(CompositeException([openapiex1, openapiex2]))
    @test OpenAPI.Clients.is_longpoll_timeout(CompositeException([openapiex1, as_taskfailedexception(openapiex2)]))
    @test OpenAPI.Clients.is_longpoll_timeout(CompositeException([openapiex1, as_taskfailedexception(openapiex1)])) == false
end

function test_request_interrupted_exception_check()
    ex1 = OpenAPI.InvocationException("request was interrupted")
    ex2 = ArgumentError("request interrupted")
    ex3 = OpenAPI.InvocationException("not request interrupted")

    @test OpenAPI.Clients.is_request_interrupted(ex1)
    @test !OpenAPI.Clients.is_request_interrupted(ex2)
    @test !OpenAPI.Clients.is_request_interrupted(ex3)

    @test OpenAPI.Clients.is_request_interrupted(as_taskfailedexception(ex1))
    @test !OpenAPI.Clients.is_request_interrupted(as_taskfailedexception(ex2))
    @test !OpenAPI.Clients.is_request_interrupted(as_taskfailedexception(ex3))

    @test OpenAPI.Clients.is_request_interrupted(CompositeException([ex1, ex2]))
    @test !OpenAPI.Clients.is_request_interrupted(CompositeException([ex2, ex3]))
end

function OpenAPI.val_format(val::AbstractString, ::Val{:testformat})
    return val == "testvalue"
end
function OpenAPI.val_format(val::Integer, ::Val{:testformat})
    return val == 111
end
function OpenAPI.val_format(val::AbstractFloat, ::Val{:testformat})
    return val == 111.111
end

function test_custom_format_validations()
    @test OpenAPI.val_format("testvalue", "testformat")
    @test !OpenAPI.val_format("invalidvalue", "testformat")
    @test OpenAPI.val_format("anyvalue", "unknownformat")

    @test OpenAPI.val_format(111, "testformat")
    @test !OpenAPI.val_format(222, "testformat")
    @test OpenAPI.val_format(111, "unknownformat")

    @test OpenAPI.val_format(111.111, "testformat")
    @test !OpenAPI.val_format(222.222, "testformat")
    @test OpenAPI.val_format(111.111, "unknownformat")

    return nothing
end

function test_format_validations()
    @test OpenAPI.val_format(typemax(Float32), "float")
    @test OpenAPI.val_format(typemax(Float64), "double")
    @test OpenAPI.val_multiple_of(10.0, 5.0)
    @test !OpenAPI.val_multiple_of(10.0, 3.0)

    b64str = String(base64encode("test string"))
    @test OpenAPI.val_format(b64str, "byte")
    @test !OpenAPI.val_format("not base64", "byte")
end

function test_validations()
    # maximum
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :maximum, 11, 10, true)
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :maximum, 11, 10, false)
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :maximum, 10, 10, true)
    @test OpenAPI.validate_param("test_param", "test_model", :maximum, 10, 10, false) === nothing
    @test OpenAPI.validate_param("test_param", "test_model", :maximum, 1, 10, false) === nothing

    # minimum
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :minimum, 10, 11, true)
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :minimum, 10, 11, false)
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :minimum, 10, 10, true)
    @test OpenAPI.validate_param("test_param", "test_model", :minimum, 10, 10, false) === nothing
    @test OpenAPI.validate_param("test_param", "test_model", :minimum, 10, 1, false) === nothing

    # maxLength, maxItems, maxProperties
    for test in (:maxLength, :maxItems, :maxProperties)
        for items in (1:10, Dict(zip(1:10, 1:10)), [1:10...])
            @test OpenAPI.validate_param("test_param", "test_model", test, items, 10) === nothing
        end
        for items in (1:2, Dict(zip(1:2, 1:2)), [1:2...])
            @test OpenAPI.validate_param("test_param", "test_model", test, items, 10) === nothing
        end
    end

    # minLength, minItems, minProperties
    for test in (:minLength, :minItems, :minProperties)
        for items in (1:10, Dict(zip(1:10, 1:10)), [1:10...])
            @test OpenAPI.validate_param("test_param", "test_model", test, items, 10) === nothing
            @test OpenAPI.validate_param("test_param", "test_model", test, items, 1) === nothing
        end
    end

    # unique
    @test OpenAPI.validate_param("test_param", "test_model", :uniqueItems, [1, 2, 3], true) === nothing
    @test OpenAPI.validate_param("test_param", "test_model", :uniqueItems, [1, 2, 2], false) === nothing
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :uniqueItems, [1, 2, 2], true)

    # pattern
    @test OpenAPI.validate_param("test_param", "test_model", :pattern, "test", r"[a-z]+") === nothing
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :pattern, "test", r"[0-9]+")

    # enum
    @test OpenAPI.validate_param("test_param", "test_model", :enum, [:a, :b, :b], [:a, :b, :c]) === nothing
    @test_throws OpenAPI.ValidationException OpenAPI.validate_param("test_param", "test_model", :enum, [:a, :b, :c, :d], [:a, :b, :c])
    
    # custom format Validations
    test_format_validations()
    test_custom_format_validations()

    return nothing
end

struct TestHasPropertyInner <: OpenAPI.APIModel
    testval::Union{Nothing,String}

    function TestHasPropertyInner(; testval=nothing)
        return new(testval)
    end
end

struct TestHasProperty <: OpenAPI.APIModel
    inner::Union{Nothing,TestHasPropertyInner}

    function TestHasProperty(; inner=nothing)
        return new(inner)
    end
end

function test_has_property()
    teststruct = TestHasProperty()

    @test !OpenAPI.Clients.haspropertyat(teststruct, :inner, :testval)
    @test !OpenAPI.Clients.haspropertyat(teststruct, "inner", "testval")
    @test !OpenAPI.Clients.haspropertyat(teststruct, :inner)

    teststruct = TestHasProperty(; inner=TestHasPropertyInner())
    @test !OpenAPI.Clients.haspropertyat(teststruct, :inner, :testval)
    @test !OpenAPI.Clients.haspropertyat(teststruct, "inner", "testval")
    @test OpenAPI.Clients.haspropertyat(teststruct, :inner)

    teststruct = TestHasProperty(; inner=TestHasPropertyInner(; testval="test"))
    @test OpenAPI.Clients.haspropertyat(teststruct, :inner, :testval)
    @test OpenAPI.Clients.haspropertyat(teststruct, "inner", "testval")
    @test OpenAPI.Clients.haspropertyat(teststruct, :inner)
    @test OpenAPI.Clients.getpropertyat(teststruct, :inner, :testval) == "test"
end


struct InvalidModel <: OpenAPI.APIModel
    test::Any

    function InvalidModel(; test=nothing)
        return new(test)
    end
end

function test_misc()
    @test isa(OpenAPI.OpenAPIException("test"), Exception)
    @test_throws Exception OpenAPI.property_type(InvalidModel(), :test)

    json = Dict{String,Any}()
    @test OpenAPI.from_json(Any, json) === json
    @test OpenAPI.from_json(String, json) == "{}"
    @test isa(OpenAPI.from_json(Dict{Any,Any}, json), Dict{Any,Any})
end

const content_disposition_tests = [
    (content_disposition="attachment; filename=content.txt", content_type="", filename="content.txt"),
    (content_disposition="attachment; filename*=UTF-8''filename.txt", content_type="", filename="filename.txt"),
    (content_disposition="attachment; filename=\"Image File\"; filename*=utf-8''UTF8ImageFile", content_type="", filename="Image File"),
    (content_disposition="attachment; filename=\"चित्त.jpg\"", content_type="", filename="चित्त.jpg"),
    (content_disposition="", content_type="", filename="response"),
    (content_disposition="", content_type="image/jpg", filename="response"),
]

function test_storefile()
    for test_data in content_disposition_tests
        headers = [
            "Content-Disposition" => test_data.content_disposition,
            "Content-Type" => test_data.content_type,
        ]
        resp = Downloads.Response("GET", "http://test/", 200, "", headers)

        @test OpenAPI.Clients.extract_filename(resp) == test_data.filename
    end

    mktempdir() do tmpdir
        test_data = content_disposition_tests[1]
        headers = [
            "Content-Disposition" => test_data.content_disposition,
            "Content-Type" => test_data.content_type,
        ]
        resp = OpenAPI.Clients.ApiResponse(Downloads.Response("GET", "http://test/", 200, "", headers))
        file_contents = "test file data"

        # test extraction of filename from headers
        result, http_response, filepath = OpenAPI.Clients.storefile(; folder=tmpdir) do
            return file_contents, resp
        end

        @test result == file_contents
        @test http_response == resp
        @test filepath == joinpath(tmpdir, test_data.filename)
        @test read(filepath, String) == file_contents

        # test overriding filename
        result, http_response, filepath = OpenAPI.Clients.storefile(; folder=tmpdir, filename="overridename.txt") do
            return file_contents, resp
        end

        @test result == file_contents
        @test http_response == resp
        @test filepath == joinpath(tmpdir, "overridename.txt")
        @test read(filepath, String) == file_contents
    end
end