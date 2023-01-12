using Test

include("client/runtests.jl")
include("client/allany/runtests.jl")

@testset "OpenAPI" begin
    # @testset "Client" begin
    #     try
    #         if get(ENV, "RUNNER_OS", "") == "Linux"
    #             run(`client/petstore_v2/start_petstore_server.sh`)
    #             run(`client/petstore_v3/start_petstore_server.sh`)
    #             sleep(20)
    #         end
    #         OpenAPIClientTests.runtests()
    #     finally
    #         if get(ENV, "RUNNER_OS", "") == "Linux"
    #             run(`client/petstore_v2/stop_petstore_server.sh`)
    #             run(`client/petstore_v3/stop_petstore_server.sh`)
    #         end
    #     end
    # end
    # if get(ENV, "RUNNER_OS", "") == "Linux"
    #     sleep(20)
    # end
    # @testset "Server" begin
    #     try
    #         if get(ENV, "RUNNER_OS", "") == "Linux"
    #             run(`server/petstore_v2/start_petstore_server.sh`)
    #             run(`server/petstore_v3/start_petstore_server.sh`)
    #             sleep(20)
    #         end
    #         OpenAPIClientTests.runtests()
    #     finally
    #         if get(ENV, "RUNNER_OS", "") == "Linux"
    #             run(`server/petstore_v2/stop_petstore_server.sh`)
    #             run(`server/petstore_v3/stop_petstore_server.sh`)
    #         end
    #     end
    # end
    # if get(ENV, "RUNNER_OS", "") == "Linux"
    #     sleep(20)
    # end
    @testset "Union types" begin
        try
            if get(ENV, "RUNNER_OS", "") == "Linux"
                run(`server/allany/start_allany_server.sh`)
                sleep(20)
                AllAnyTests.runtests()
            end
        finally
            if get(ENV, "RUNNER_OS", "") == "Linux"
                run(`server/allany/stop_allany_server.sh`)
            end
        end
    end
end