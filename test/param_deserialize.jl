using Test

using OpenAPI.Servers: deep_dict_repr
using OpenAPI: deep_object_to_array
@testset "Test deep_dict_repr" begin
    @testset "Single level object" begin
        query_string = Dict("key1" => "value1", "key2" => "value2")
        expected = Dict("key1" => "value1", "key2" => "value2")
        @test deep_dict_repr(query_string) == expected
    end

    @testset "Nested object" begin
        query_string = Dict("outer[inner]" => "value")
        expected = Dict("outer" => Dict("inner" => "value"))
        @test deep_dict_repr(query_string) == expected
    end
    @testset "Deeply nested object" begin
        query_string = Dict("a[b][c][d]" => "value")
        expected = Dict("a" => Dict("b" => Dict("c" => Dict("d" => "value"))))
        @test deep_dict_repr(query_string) == expected
    end

    @testset "Multiple nested objects" begin
        query_string = Dict("a[b]" => "value1", "a[c]" => "value2")
        expected = Dict("a" => Dict("b" => "value1", "c" => "value2"))
        @test deep_dict_repr(query_string) == expected
    end

    @testset "List of values" begin
        query_string = Dict("a[0]" => "value1", "a[1]" => "value2")
        expected = Dict("a" => Dict("0" => "value1", "1" => "value2"))
        @test deep_dict_repr(query_string) == expected
    end

    @testset "Mixed structure" begin
        query_string =
            Dict("a[b]" => "value1", "a[c][0]" => "value2", "a[c][1]" => "value3")
        expected = Dict(
            "a" => Dict("b" => "value1", "c" => Dict("0" => "value2", "1" => "value3")),
        )
        @test deep_dict_repr(query_string) == expected
    end

    @testset "deep_object_to_array" begin
        example = Dict(
            "a" => Dict("b" => "value1", "c" => Dict("0" => "value2", "1" => "value3")),
        )
        @test deep_object_to_array(example) == example
        @test deep_object_to_array(example["a"]["c"]) == ["value2", "value3"]
    end

    @testset "Blank values" begin
        query_string = Dict("a[b]" => "", "a[c]" => "")
        expected = Dict("a" => Dict("b" => "", "c" => ""))
        @test deep_dict_repr(query_string) == expected
    end

    @testset "Complex nested structure" begin
        query_string =
            Dict("a[b][c][d]" => "value1", "a[b][c][e]" => "value2", "a[f]" => "value3")
        expected = Dict(
            "a" => Dict(
                "b" => Dict("c" => Dict("d" => "value1", "e" => "value2")),
                "f" => "value3",
            ),
        )
        @test deep_dict_repr(query_string) == expected
    end
    @testset "Complex nested structure with numbers and nessted" begin
        query_string = Dict{String,String}(
            "filter[0][name]" => "name",
            "filter[0][data][0]" => "Dog",
            "pagination[type]" => "offset",
            "pagination[page]" => "1",
            "filter[0][type]" => "FilterSet",
            "pagination[per_page]" => "5",
            "pagination[foo]" => "5.0",
        )
        expected = Dict(
            "pagination" => Dict(
                "page" => "1",
                "per_page" => "5",
                "type" => "offset",
                "foo" => "5.0",
            ),
            "filter" => Dict(
                "0" => Dict(
                    "name" => "name",
                    "data" => Dict("0" => "Dog"),
                    "type" => "FilterSet",
                ),
            ),
        )
        d = deep_dict_repr(query_string)
        @test d["pagination"] == expected["pagination"]
        @test d["filter"] == expected["filter"]
    end

end
