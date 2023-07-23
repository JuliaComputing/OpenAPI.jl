module OpenAPIGenPetStoreV3Tests

include(joinpath(@__DIR__, "petstore", "src", "OpenAPIGenPetStoreClient.jl"))
using .OpenAPIGenPetStoreClient
using Test

include("petstore_test_petapi.jl")
include("petstore_test_userapi.jl")
include("petstore_test_storeapi.jl")

const server = "http://127.0.0.1:8081/v3"

function runtests(; test_file_upload=false)
    @testset "petstore v3" begin
        TestUserApi.test(server)
        TestStoreApi.test(server)
        TestPetApi.test(server; test_file_upload=test_file_upload)
    end
end
end # module OpenAPIGenPetStoreV3Tests
