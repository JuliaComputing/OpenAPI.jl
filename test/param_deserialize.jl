using Test

using OpenAPI.Servers: deep_dict_repr, get_param, to_param
using OpenAPI: deep_object_to_array, ValidationException

@testset "Case-insensitive header param lookup" begin
    # HTTP.jl 2.x canonicalizes incoming request header names (e.g. the wire header
    # "api_key" arrives as "Api_key"), while 1.x preserves the sent case. Header field
    # names are case-insensitive per RFC, so server param lookup must resolve them
    # regardless of the HTTP.jl version. See get_param in src/server.jl.
    canonicalized = Dict{String,String}("Api_key" => "secret", "Uuid_parameter" => "abc")

    @testset "get_param resolves canonicalized keys" begin
        @test get_param(canonicalized, "api_key", false) == "secret"
        @test get_param(canonicalized, "uuid_parameter", false) == "abc"
        # required param present only under its canonicalized key must not throw
        @test get_param(canonicalized, "api_key", true) == "secret"
    end

    @testset "exact match still wins" begin
        # an exact key takes precedence over any case-insensitive fallback
        mixed = Dict{String,String}("api_key" => "exact", "Api_key" => "canon")
        @test get_param(mixed, "api_key", false) == "exact"
    end

    @testset "genuinely missing param" begin
        @test get_param(canonicalized, "missing", false) === nothing
        @test_throws ValidationException get_param(canonicalized, "missing", true)
    end

    @testset "to_param end-to-end (as generated code calls it)" begin
        @test to_param(String, canonicalized, "api_key") == "secret"
        @test to_param(String, canonicalized, "uuid_parameter"; required=true) == "abc"
    end
end
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
