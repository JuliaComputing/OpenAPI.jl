module TestUserApi

using ..PetStoreClient
using Test
using Random
using JSON
using URIs
using OpenAPI
using OpenAPI.Clients
import OpenAPI.Clients: Client, Ctx, ApiException, DEFAULT_TIMEOUT_SECS, with_timeout, set_timeout, set_user_agent, set_cookie

const TEST_USER = "jloac"
const TEST_USER1 = "jloac1"
const TEST_USER2 = "jloac2"
const PRESET_TEST_USER = "user1"    # this is the username that works for get user requests (as documented in the test docker container API)

function test_404(uri)
    @info("Error handling")
    client = Client(uri*"_invalid")
    api = UserApi(client)

    api_return, http_resp = login_user(api, TEST_USER, "testpassword")
    @test http_resp.status == 404
    @test api_return === nothing

    client = Client("http://_invalid/")
    api = UserApi(client)

    try
        login_user(api, TEST_USER, "testpassword")
        @error("ApiException not thrown")
    catch ex
        @test isa(ex, ApiException)
        @test startswith(ex.reason, "Could not resolve host")
    end    
end

function test_set_methods()
    @info("Error handling")
    client = Client("http://_invalid/")

    @test client.timeout[] == DEFAULT_TIMEOUT_SECS

    with_timeout(client, DEFAULT_TIMEOUT_SECS + 10) do client
        @test client.timeout[] == DEFAULT_TIMEOUT_SECS + 10
    end
    @test client.timeout[] == DEFAULT_TIMEOUT_SECS

    api = UserApi(client)
    with_timeout(api, DEFAULT_TIMEOUT_SECS + 10) do api
        @test api.client.timeout[] == DEFAULT_TIMEOUT_SECS + 10
    end
    @test client.timeout[] == DEFAULT_TIMEOUT_SECS

    set_timeout(client, DEFAULT_TIMEOUT_SECS + 10)
    @test client.timeout[] == DEFAULT_TIMEOUT_SECS + 10

    @test isempty(client.headers)
    set_user_agent(client, "007")
    set_cookie(client, "crumbly")
    @test client.headers["User-Agent"] == "007"
    @test client.headers["Cookie"] == "crumbly"
end

function test_login_user_hook(ctx::Ctx)
    ctx.header["actual_password"] = "testpassword"
    ctx
end

function test_login_user_hook(resource_path::AbstractString, body::Any, headers::Dict{String,String})
    uri = URIs.parse_uri(resource_path)    
    qparams = URIs.queryparams(uri)
    qparams["password"] = headers["actual_password"]
    delete!(headers, "actual_password")
    resource_path = string(URIs.URI(uri; query=escapeuri(qparams)))

    (resource_path, body, headers)
end

function test_userhook(uri)
    @info("User hook")
    client = Client(uri; pre_request_hook=test_login_user_hook)
    api = UserApi(client)

    login_result, http_resp = login_user(api, TEST_USER, "wrongpassword")
    @test http_resp.status == 200
    @test !isempty(login_result)
    result = JSON.parse(login_result)
    @test startswith(result["message"], "logged in user session")
    @test result["code"] == 200
end

function test_parallel(uri)
    @info("Parallel usage")
    client = Client(uri)
    api = UserApi(client)

    for gcidx in 1:100
        @sync begin
            for idx in 1:10^3
                @async begin
                    @debug("[$idx] UserApi Parallel begin")
                    login_result = login_user(api, TEST_USER, "testpassword")
                    @test !isempty(login_result)
                    result = JSON.parse(login_result)
                    @test startswith(result["message"], "logged in user session")
                    @test result["code"] == 200

                    @test_throws ApiException get_user_by_name(api, randstring())
                    @test_throws ApiException get_user_by_name(api, TEST_USER)

                    logout_result = logout_user(api)
                    @test logout_result === nothing
                    @debug("[$idx] UserApi Parallel end")
                end
            end
        end
        GC.gc()
        @info("outer loop $gcidx")
    end
    nothing
end

function test(uri)
    @info("UserApi")
    client = Client(uri)
    api = UserApi(client)

    @info("UserApi - login_user")
    login_result, http_resp = login_user(api, TEST_USER, "testpassword")
    @test !isempty(login_result)
    @test http_resp.status == 200

    @info("UserApi - create_user")
    user1 = User(; id=100, username=TEST_USER1, firstName="test1", lastName="user1", email="jloac1@example.com", password="testpass1", phone="1000000001", userStatus=0)
    api_return, http_resp = create_user(api, user1)
    @test api_return === nothing
    @test http_resp.status == 200

    @info("UserApi - create_users_with_array_input")
    user2 = User(; id=200, username=TEST_USER2, firstName="test2", lastName="user2", email="jloac2@example.com", password="testpass2", phone="1000000002", userStatus=0)
    api_return, http_resp = create_users_with_array_input(api, [user1, user2])
    @test api_return === nothing
    @test http_resp.status == 200

    @info("UserApi - create_users_with_array_input")
    api_return, http_resp = create_users_with_array_input(api, [user1, user2])
    @test api_return === nothing
    @test http_resp.status == 200

    @info("UserApi - get_user_by_name")
    getuser_result, http_resp = get_user_by_name(api, randstring())
    @test getuser_result === nothing
    @test http_resp.status == 404
    getuser_result, http_resp = get_user_by_name(api, TEST_USER)
    @test getuser_result === nothing
    @test http_resp.status == 404
    getuser_result, http_resp = get_user_by_name(api, PRESET_TEST_USER)
    @test isa(getuser_result, User)
    @test http_resp.status == 200

    @info("UserApi - update_user")
    api_return, http_resp = update_user(api, TEST_USER2, getuser_result)
    @test api_return === nothing
    @test http_resp.status == 200
    @info("UserApi - delete_user")
    api_return, http_resp = delete_user(api, TEST_USER2)
    @test api_return === nothing
    @test http_resp.status == 200

    @info("UserApi - logout_user")
    logout_result, http_resp = logout_user(api)
    @test logout_result === nothing
    @test http_resp.status == 200

    nothing
end

end # module TestUserApi
