module AllAnyTests

include(joinpath(@__DIR__, "AllAnyClient", "src", "AllAnyClient.jl"))
using .AllAnyClient
using Test
using JSON
using OpenAPI
using OpenAPI.Clients
import OpenAPI.Clients: Client

const M = AllAnyClient
const server = "http://127.0.0.1:8081"

const mapped_cat = M.Cat(pet_type="cat", hunts=true, age=5)
const mapped_dog = M.Dog(pet_type="dog", bark=true, breed="Husky")
const cat = M.Cat(pet_type="Cat", hunts=true, age=5)
const dog = M.Dog(pet_type="Dog", bark=true, breed="Husky")

function pet_equals(pet1, pet2)
    @warn("pet_equals not implemented for $(typeof(pet1)) and $(typeof(pet2))")
    false
end
function pet_equals(cat1::M.Cat, cat2::M.Cat)
    cat1.pet_type == cat2.pet_type && cat1.hunts == cat2.hunts && cat1.age == cat2.age
end
function pet_equals(dog1::M.Dog, dog2::M.Dog)
    dog1.pet_type == dog2.pet_type && dog1.bark == dog2.bark && dog1.breed == dog2.breed
end
pet_equals(pet1::OpenAPI.UnionAPIModel, pet2::OpenAPI.UnionAPIModel) = pet_equals(pet1.value, pet2.value)
basetype_equals(val1::OpenAPI.UnionAPIModel, val2::OpenAPI.UnionAPIModel) = val1.value == val2.value

function runtests()
    @testset "allany" begin
        @info("AllAnyApi")
        client = Client(server)
        api = M.DefaultApi(client)
    
        pet = M.AnyOfMappedPets(mapped_cat)
        api_return, http_resp = echo_anyof_mapped_pets_post(api, pet)
        @test pet_equals(api_return, pet)
    
        pet = M.AnyOfPets(dog)
        api_return, http_resp = echo_anyof_pets_post(api, pet)
        @test pet_equals(api_return, pet)
    
        pet = M.OneOfMappedPets(mapped_dog)
        api_return, http_resp = echo_oneof_mapped_pets_post(api, pet)
        @test pet_equals(api_return, pet)
    
        pet = M.OneOfPets(cat)
        api_return, http_resp = echo_oneof_pets_post(api, pet)
        @test pet_equals(api_return, pet)

        val = M.AnyOfBaseType("hello")
        api_return, http_resp = echo_anyof_base_type_post(api, val)
        @test basetype_equals(api_return, val)

        val = M.OneOfBaseType(100.1)
        api_return, http_resp = echo_oneof_base_type_post(api, val)
        @test basetype_equals(api_return, val)

        arr = M.TypeWithAllArrayTypes()
        arr.oneofbase = [M.OneOfBaseType(1), M.OneOfBaseType(2)]
        arr.anyofbase = [M.AnyOfBaseType("hello"), M.AnyOfBaseType("world")]
        arr.oneofpets = [M.OneOfPets(cat), M.OneOfPets(dog)]
        arr.anyofpets = [M.AnyOfPets(cat), M.AnyOfPets(dog)]

        api_return, http_resp = echo_arrays_post(api, arr)

        for idx in 1:2
            @test basetype_equals(arr.oneofbase[idx], api_return.oneofbase[idx])
            @test basetype_equals(arr.anyofbase[idx], api_return.anyofbase[idx])
            @test pet_equals(arr.oneofpets[idx], api_return.oneofpets[idx])
            @test pet_equals(arr.anyofpets[idx], api_return.anyofpets[idx])
        end
    end
end

function test_debug()
    @testset "stderr verbose mode" begin
        @info("stderr verbose mode")
        client = Client(server; verbose=true)
        api = M.DefaultApi(client)
    
        pipe = Pipe()
        redirect_stderr(pipe) do
            pet = M.AnyOfMappedPets(mapped_cat)
            api_return, http_resp = echo_anyof_mapped_pets_post(api, pet)
            @test pet_equals(api_return, pet)
        end
        out_str = String(readavailable(pipe))
        @test occursin("HTTP/1.1 200 OK", out_str)
    end
    @testset "debug log verbose mode" begin
        @info("debug log verbose mode")
        client = Client(server; verbose=OpenAPI.Clients.default_debug_hook)
        api = M.DefaultApi(client)
    
        pipe = Pipe()
        redirect_stderr(pipe) do
            pet = M.AnyOfMappedPets(mapped_cat)
            api_return, http_resp = echo_anyof_mapped_pets_post(api, pet)
            @test pet_equals(api_return, pet)
        end
        out_str = String(readavailable(pipe))
        @test occursin("HTTP/1.1 200 OK", out_str)
    end
    @testset "custom verbose function" begin
        @info("custom verbose function")
        messages = Any[]
        client = Client(server; verbose=(type,message)->push!(messages, (type,message)))
        api = M.DefaultApi(client)
    
        pet = M.AnyOfMappedPets(mapped_cat)
        api_return, http_resp = echo_anyof_mapped_pets_post(api, pet)
        @test pet_equals(api_return, pet)

        data_out = filter(messages) do elem
            elem[1] == "DATA OUT"
        end
        @test !isempty(data_out)
        iob = IOBuffer()
        for (type, message) in data_out
            write(iob, message)
        end
        data_out_str = String(take!(iob))
        data_out_json = JSON.parse(data_out_str)
        @test data_out_json["pet_type"] == "cat"
        @test data_out_json["hunts"] == true
        @test data_out_json["age"] == 5

        data_in = filter(messages) do elem
            elem[1] == "DATA IN"
        end
        @test !isempty(data_in)
        iob = IOBuffer()
        for (type, message) in data_in
            write(iob, message)
        end
        data_in_str = String(take!(iob))
        data_in_str = strip(split(data_in_str, "\n")[2])
        data_in_json = JSON.parse(data_in_str)
        @test data_in_json["pet_type"] == "cat"
        @test data_in_json["hunts"] == true
        @test data_in_json["age"] == 5
    end
end

end # module AllAnyTests