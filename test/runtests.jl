using Test

include("client/runtests.jl")

@testset "OpenAPI" begin
    @testset "Client" begin
        try
            run(`client/petstore_v2/start_petstore_server.sh`)
            run(`client/petstore_v3/start_petstore_server.sh`)
            sleep(20)
            OpenAPIClientTests.runtests()
        finally
            run(`client/petstore_v2/stop_petstore_server.sh`)
            run(`client/petstore_v3/stop_petstore_server.sh`)
        end
    end
    sleep(20)
    @testset "Server" begin
        try
            run(`server/petstore_v2/start_petstore_server.sh`)
            run(`server/petstore_v3/start_petstore_server.sh`)
            sleep(20)
            OpenAPIClientTests.runtests()
        finally
            run(`server/petstore_v2/stop_petstore_server.sh`)
            run(`server/petstore_v3/stop_petstore_server.sh`)
        end
    end
end