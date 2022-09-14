module PetStoreV2Tests

include(joinpath(@__DIR__, "petstore", "src", "PetStoreClient.jl"))
using .PetStoreClient
using Test

include("petstore_test_petapi.jl")
include("petstore_test_userapi.jl")
include("petstore_test_storeapi.jl")

const server = "http://127.0.0.1:8080/v2"

function test_misc()
    TestUserApi.test_404(server)
    TestUserApi.test_userhook(server)
    TestUserApi.test_set_methods()
end

function test_stress()
    TestUserApi.test_parallel(server)
end

function petstore_tests()
    TestUserApi.test(server)
    TestStoreApi.test(server)
    TestPetApi.test(server)
end

function runtests()
    @testset "petstore v2" begin
        @testset "miscellaneous" begin
            test_misc()
        end
        @testset "petstore apis" begin
            petstore_tests()
        end
        if get(ENV, "STRESS_PETSTORE", "false") == "true"
            @testset "stress" begin
                test_stress()
            end
        end
    end
end
end # module PetStoreV2Tests