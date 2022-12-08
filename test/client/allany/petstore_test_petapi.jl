module TestPetApi

using ..PetStoreClient
using Test
using OpenAPI
using OpenAPI.Clients
import OpenAPI.Clients: Client

function test(uri)
    @info("PetApi")
    client = Client(uri)
    api = PetApi(client)

    tag1 = Tag(;id=10, name="juliacat")
    tag2 = Tag(;id=11, name="white")
    cat = Category(;id=10, name="cat")

    @test_throws OpenAPI.ValidationException Pet(;id=10, category=cat, name="felix", photoUrls=nothing, tags=[tag1, tag2], status="invalid-status")

    pet = Pet(;id=10, category=cat, name="felix", photoUrls=nothing, tags=[tag1,tag2], status="pending")

    @info("PetApi - add_pet")
    api_return, http_resp = add_pet(api, pet)
    @test api_return === nothing
    @test http_resp.status == 200

    @info("PetApi - update_pet")
    pet.status = "available"
    api_return, http_resp = update_pet(api, pet)
    @test api_return === nothing
    @test http_resp.status == 200

    # @info("PetApi - update_pet_with_form")
    # @test update_pet_with_form(api, 10; in_name="meow") === nothing

    @info("PetApi - get_pet_by_id")
    pet10, http_resp = get_pet_by_id(api, Int64(10))
    @test pet10.id == 10
    @test http_resp.status == 200

    @info("PetApi - find_pets_by_status")
    unsold = ["available", "pending"]
    pets, http_resp = find_pets_by_status(api, unsold)
    @test isa(pets, Vector{Pet})
    @test http_resp.status == 200
    @info("PetApi - find_pets_by_status", npets=length(pets))
    for p in pets
        @test p.status in unsold
    end

    @info("PetApi - delete_pet")
    api_return, http_resp = delete_pet(api, Int64(10))
    @test api_return === nothing
    @test http_resp.status == 200

    # does not work yet. issue: https://github.com/JuliaWeb/Requests.jl/issues/139
    #@info("PetApi - upload_file")
    #img = joinpath(dirname(@__FILE__), "cat.png")
    #resp, http_resp = upload_file(api, 10; additionalMetadata="juliacat pic", file=img)
    #@test isa(resp, ApiResponse)
    #@test resp.code == 200
    #@info("PetApi - upload_file", typ=get_field(resp, "type"), message=get_field(resp, "message"))

    nothing
end

end # module TestPetApi
