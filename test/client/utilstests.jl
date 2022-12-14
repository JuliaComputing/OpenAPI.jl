using OpenAPI
using OpenAPI.Clients
using Test

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
    test_custom_format_validations()
    return nothing
end