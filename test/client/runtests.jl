module OpenAPIClientTests

using OpenAPI
using OpenAPI.Clients
using Test

include("utilstests.jl")
include("petstore_v3/runtests.jl")
include("petstore_v2/runtests.jl")

function runtests()
    @testset "Client" begin
        @testset "Utils" begin
            test_longpoll_exception_check()
            test_request_interrupted_exception_check()
            test_date()
            test_misc()
            test_has_property()
        end
        @testset "Validations" begin
            test_validations()
        end
        @testset "Petstore" begin
            if get(ENV, "RUNNER_OS", "") == "Linux"
                @testset "V3" begin
                    @info("Running petstore v3 tests")
                    PetStoreV3Tests.runtests()
                end
                @testset "V2" begin
                @info("Running petstore v2 tests")
                PetStoreV2Tests.runtests()
                end
            else
                @info("Skipping petstore tests in non Linux environment (can not run petstore docker on OSX or Windows)")
            end
        end
    end
end

end # module OpenAPIClientTests