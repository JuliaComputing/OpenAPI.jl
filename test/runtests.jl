using Test, HTTP

include("testutils.jl")
include("client/runtests.jl")
include("client/allany/runtests.jl")

@testset "OpenAPI" begin
    @testset "Client" begin
        try
            if run_tests_with_servers
                run(`client/petstore_v2/start_petstore_server.sh`)
                run(`client/petstore_v3/start_petstore_server.sh`)
                sleep(20) # let servers start
            end
            OpenAPIClientTests.runtests()
        finally
            if run_tests_with_servers
                run(`client/petstore_v2/stop_petstore_server.sh`)
                run(`client/petstore_v3/stop_petstore_server.sh`)
            end
        end
    end
    run_tests_with_servers && sleep(20) # avoid port conflicts
    @testset "Server" begin
        v2_ret = v2_out = v3_ret = v3_out = nothing
        servers_running = true

        try
            if run_tests_with_servers
                v2_ret, v2_out = run_server(joinpath(@__DIR__, "server", "petstore_v2", "petstore_server.jl"))
                v3_ret, v3_out = run_server(joinpath(@__DIR__, "server", "petstore_v3", "petstore_server.jl"))
                servers_running &= wait_server(8080)
                servers_running &= wait_server(8081)
            else
                servers_running = false                
            end
            servers_running && OpenAPIClientTests.runtests()
        finally
            if run_tests_with_servers
                stop_server(8080, v2_ret, v2_out)
                stop_server(8081, v3_ret, v3_out)
            end
        end
    end
    run_tests_with_servers && sleep(20) # avoid port conflicts
    @testset "Union types" begin
        ret = out = nothing
        servers_running = true

        try
            if run_tests_with_servers
                ret, out = run_server(joinpath(@__DIR__, "server", "allany", "allany_server.jl"))
                servers_running &= wait_server(8081)
                AllAnyTests.runtests()
            else
                servers_running = false
            end
        finally
            run_tests_with_servers && stop_server(8081, ret, out)
        end
    end
end