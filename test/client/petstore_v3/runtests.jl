module PetStoreV3Tests

include(joinpath(@__DIR__, "petstore", "src", "PetStoreClient.jl"))
using .PetStoreClient
using Test

include("petstore_test_petapi.jl")
include("petstore_test_userapi.jl")
include("petstore_test_storeapi.jl")

const server = "http://127.0.0.1:8081/v3"

function test_misc(httplib::Symbol)
    TestUserApi.test_404(server, httplib)
    TestUserApi.test_userhook(server, httplib)
    TestUserApi.test_set_methods()
end

function test_stress(httplib::Symbol)
    TestUserApi.test_parallel(server, httplib)
end

function petstore_tests(httplib::Symbol; test_file_upload=false)
    TestUserApi.test(server, httplib)
    TestStoreApi.test(server, httplib)
    TestPetApi.test(server, httplib; test_file_upload=test_file_upload)
end

function runtests(httplib::Symbol; test_file_upload=false)
    @testset "petstore v3" begin
        @testset "miscellaneous" begin
            test_misc(httplib)
        end
        @testset "petstore apis" begin
            petstore_tests(httplib; test_file_upload=test_file_upload)
        end
        if get(ENV, "STRESS_PETSTORE", "false") == "true"
            @testset "stress" begin
                test_stress(httplib)
            end
        end
    end
end
end # module PetStoreV3Tests
