module TestModelGen
    using OpenAPI
    using Test

    include("ModelGenClient/src/ModelGenClient.jl")
    include("ModelGenServer/src/ModelGenServer.jl")

    function test_modelgen(testmodel)
        @test testmodel.limited_by == "time"
        @test testmodel.default_date == OpenAPI.str2date("2011-11-11")
        @test testmodel.default_datetime == OpenAPI.str2zoneddatetime("2011-11-11T11:11:11Z")
        @test testmodel.max_val == 100
        @test testmodel.compute in ["cpu", "gpu"]
    end

    function runtests()
        test_modelgen(ModelGenClient.TestModel(; compute="cpu"));
        test_modelgen(ModelGenServer.TestModel(; compute="gpu"));
    end
end # module TestModelGen
