module AllAnyTests

include(joinpath(@__DIR__, "AllAnyClient", "src", "AllAnyClient.jl"))
using .AllAnyClient
using Test
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
    end
end
end # module AllAnyTests