using OpenAPI.Clients: deep_object_serialize

@testset "Test deep_object_serialize" begin
    @testset "Single level object" begin
        dict = Dict("key1" => "value1", "key2" => "value2")
        expected = Dict("key1" => "value1", "key2" => "value2")
        @test deep_object_serialize(dict) == expected
    end

    @testset "Nested object" begin
        dict = Dict("outer" => Dict("inner" => "value"))
        expected = Dict("outer[inner]" => "value")
        @test deep_object_serialize(dict) == expected
    end

    @testset "Deeply nested object" begin
        dict = Dict("a" => Dict("b" => Dict("c" => Dict("d" => "value"))))
        expected = Dict("a[b][c][d]" => "value")
        @test deep_object_serialize(dict) == expected
    end

    @testset "Multiple nested objects" begin
        dict = Dict("a" => Dict("b" => "value1", "c" => "value2"))
        expected = Dict("a[b]" => "value1", "a[c]" => "value2")
        @test deep_object_serialize(dict) == expected
    end

    @testset "Dictionary represented array" begin
        dict = Dict("a" => ["value1", "value2"])
        expected = Dict("a[0]" => "value1", "a[1]" => "value2")
        @test deep_object_serialize(dict) == expected
    end

    @testset "Mixed structure" begin
        dict = Dict("a" => Dict("b" => "value1", "c" => ["value2", "value3"]))
        expected = Dict("a[b]" => "value1", "a[c][0]" => "value2", "a[c][1]" => "value3")
        @test deep_object_serialize(dict) == expected
    end

    @testset "Blank values" begin
        dict = Dict("a" => Dict("b" => "", "c" => ""))
        expected = Dict("a[b]" => "", "a[c]" => "")
        @test deep_object_serialize(dict) == expected
    end
end
