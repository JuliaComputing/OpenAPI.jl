module TimeoutTests

include(joinpath(@__DIR__, "TimeoutTestClient", "src", "TimeoutTestClient.jl"))
using .TimeoutTestClient
using Test
using JSON
using HTTP
using OpenAPI
using OpenAPI.Clients
import OpenAPI.Clients: Client, with_timeout, ApiException

const M = TimeoutTestClient
const server = "http://127.0.0.1:8081"

function test_normal_operation(client, delay_secs)
    @info("timeout default, delay $delay_secs secs")
    api = M.DefaultApi(client)
    api_return, http_resp = delayresponse_get(api, delay_secs)
    @test http_resp.status == 200
    @test api_return.delay_seconds == string(delay_secs)
end

function test_timeout_operation(client, timeout_secs, delay_secs)
    @info("timeout $timeout_secs secs, delay $delay_secs secs")
    with_timeout(client, timeout_secs) do client
        try
            api = M.DefaultApi(client)
            delayresponse_get(api, delay_secs)
            error("Timeout not thrown")
        catch ex
            @test isa(ex, ApiException)
            @test ex.status == 0
            @test startswith(ex.reason, "Operation timed out")
        end
    end
end

function runtests()
    @testset "timeout_tests" begin
        @info("TimeoutTest")
        client = Client(server)

        test_normal_operation(client, 10)

        for timeout_secs in (5, 120) # test different timeouts
            delay_secs = timeout_secs + 60
            test_timeout_operation(client, timeout_secs, delay_secs)

            # but the client should still be usable
            test_normal_operation(client, 10)
        end

        # also test a long delay in general (default libcurl timeout is 0)
        test_normal_operation(client, 160)
    end
end
    
end # module TimeoutTests
