module OpenAPIClientTests

using OpenAPI
using OpenAPI.Clients
using Test

include("utilstests.jl")
include("petstore_v3/runtests.jl")
include("petstore_v2/runtests.jl")
include("openapigenerator_petstore_v3/runtests.jl")

function runtests(; skip_petstore=false, test_file_upload=false)
    @testset "Client" begin
        @testset "deepObj query param serialization" begin
            include("client/param_serialize.jl")
        end
        @testset "Utils" begin
            test_longpoll_exception_check()
            test_request_interrupted_exception_check()
            test_date()
            test_misc()
            test_has_property()
            test_storefile()
        end
        @testset "Validations" begin
            test_validations()
        end
        if !skip_petstore
            @testset "Petstore" begin
                if get(ENV, "RUNNER_OS", "") == "Linux"
                    @testset "V3" begin
                        @info("Running petstore v3 tests")
                        PetStoreV3Tests.runtests(; test_file_upload=test_file_upload)
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
end

function run_openapigenerator_tests(; test_file_upload=false)
    @testset "OpenAPIGeneratorPetstoreClient" begin
        if get(ENV, "RUNNER_OS", "") == "Linux"
            @info("Running petstore v3 tests")
            OpenAPIGenPetStoreV3Tests.runtests(; test_file_upload=test_file_upload)
        else
            @info("Skipping petstore tests in non Linux environment (can not run petstore docker on OSX or Windows)")
        end
    end
end

end # module OpenAPIClientTests
