using Test, HTTP

include("chunkreader_tests.jl")
include("testutils.jl")
include("modelgen/testmodelgen.jl")
include("client/runtests.jl")
include("client/allany/runtests.jl")
include("forms/forms_client.jl")
include("client/timeouttest/runtests.jl")
include("deep_object/deep_client.jl")

@testset "OpenAPI" begin
    include("param_deserialize.jl")
    @testset "ModelGen" begin
        TestModelGen.runtests()
    end
    @testset "Chunk Readers" begin
        ChunkReaderTests.runtests()
    end
    @testset "Petstore Client" begin
        try
            if run_tests_with_servers && !openapi_generator_env
                run(`bash client/petstore_v2/start_petstore_server.sh`)
                run(`bash client/petstore_v3/start_petstore_server.sh`)
                sleep(20) # let servers start
            end
            OpenAPIClientTests.runtests(; skip_petstore=openapi_generator_env, test_file_upload=false)
        finally
            if run_tests_with_servers && !openapi_generator_env
                run(`bash client/petstore_v2/stop_petstore_server.sh`)
                run(`bash client/petstore_v3/stop_petstore_server.sh`)
            end
        end
    end
    run_tests_with_servers && !openapi_generator_env && sleep(20) # avoid port conflicts
    @testset "Petstore Server" begin
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
            servers_running && OpenAPIClientTests.runtests(; test_file_upload=true)
        finally
            if run_tests_with_servers && !servers_running
                # we probably had an error starting the servers
                v2_out_str = isnothing(v2_out) ? "" : String(take!(v2_out))
                v3_out_str = isnothing(v3_out) ? "" : String(take!(v3_out))
                @warn("Servers not running", v2_ret=v2_ret, v2_out_str, v3_ret=v3_ret, v3_out_str)
            end
            if run_tests_with_servers && servers_running
                stop_server(8080, v2_ret, v2_out)
                stop_server(8081, v3_ret, v3_out)
            end
        end
    end
    run_tests_with_servers && sleep(20) # avoid port conflicts
    @testset "Petstore Server (openapi-generator)" begin
        v3_ret = v3_out = nothing
        servers_running = true

        try
            if run_tests_with_servers
                v3_ret, v3_out = run_server(joinpath(@__DIR__, "server", "openapigenerator_petstore_v3", "petstore_server.jl"))
                servers_running &= wait_server(8081)
            else
                servers_running = false
            end
            servers_running && OpenAPIClientTests.run_openapigenerator_tests(; test_file_upload=true)
        finally
            if run_tests_with_servers && !servers_running
                # we probably had an error starting the servers
                v3_out_str = isnothing(v3_out) ? "" : String(take!(v3_out))
                @warn("Servers not running", v3_ret=v3_ret, v3_out_str)
            end
            if run_tests_with_servers && servers_running
                stop_server(8081, v3_ret, v3_out)
            end
        end
    end
    run_tests_with_servers && sleep(20) # avoid port conflicts
    @testset "Forms and File Uploads" begin
        ret = out = nothing
        servers_running = true

        try
            if run_tests_with_servers
                ret, out = run_server(joinpath(@__DIR__, "forms", "forms_server.jl"))
                servers_running &= wait_server(8081)
                FormsV3Client.runtests()
            else
                servers_running = false
            end
        finally
            if run_tests_with_servers && !servers_running
                # we probably had an error starting the servers
                out_str = isnothing(out) ? "" : String(take!(out))
                @warn("Servers not running", ret=ret, out_str)
            end
            run_tests_with_servers && servers_running && stop_server(8081, ret, out)
        end
    end
    run_tests_with_servers && sleep(20) # avoid port conflicts
    @testset "DeepObject tests" begin
        ret = out = nothing
        servers_running = true

        try
            if run_tests_with_servers
                ret, out = run_server(joinpath(@__DIR__, "deep_object", "deep_server.jl"))
                servers_running &= wait_server(8081)
                DeepClientTest.runtests()
            else
                servers_running = false
            end
        finally
            if run_tests_with_servers && !servers_running
                # we probably had an error starting the servers
                out_str = isnothing(out) ? "" : String(take!(out))
                @warn("Servers not running", ret=ret, out_str)
            end
            run_tests_with_servers && servers_running && stop_server(8081, ret, out)
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
            if run_tests_with_servers && !servers_running
                # we probably had an error starting the servers
                out_str = isnothing(out) ? "" : String(take!(out))
                @warn("Servers not running", ret=ret, out_str)
            end
            run_tests_with_servers && stop_server(8081, ret, out)
        end
    end
    run_tests_with_servers && sleep(20) # avoid port conflicts
    @testset "Debug and Verbose" begin
        ret = out = nothing
        servers_running = true

        try
            if run_tests_with_servers
                ret, out = run_server(joinpath(@__DIR__, "server", "allany", "allany_server.jl"))
                servers_running &= wait_server(8081)
                if VERSION >= v"1.7"
                    AllAnyTests.test_debug()
                end
            else
                servers_running = false
            end
        finally
            if run_tests_with_servers && !servers_running
                # we probably had an error starting the servers
                out_str = isnothing(out) ? "" : String(take!(out))
                @warn("Servers not running", ret=ret, out_str)
            end
            run_tests_with_servers && servers_running && stop_server(8081, ret, out)
        end
    end

    @testset "Helper Methods" begin
        AllAnyTests.test_http_resp()
    end

    @testset "Timeout Handling" begin
        ret = out = nothing
        servers_running = true

        try
            if run_tests_with_servers
                ret, out = run_server(joinpath(@__DIR__, "server", "timeouttest", "timeouttest_server.jl"))
                servers_running &= wait_server(8081)
                TimeoutTests.runtests()
            else
                servers_running = false
            end
        finally
            if run_tests_with_servers && !servers_running
                # we probably had an error starting the servers
                out_str = isnothing(out) ? "" : String(take!(out))
                @warn("Servers not running", ret=ret, out_str)
            end
            run_tests_with_servers && stop_server(8081, ret, out)
        end
    end
    run_tests_with_servers && sleep(20) # avoid port conflicts


end
