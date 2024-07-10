module DeepClientTest

include("DeepClient/src/DeepClient.jl")
using .DeepClient
using .DeepClient.OpenAPI.Clients: Client
using .DeepClient: FindPetsByStatusStatusParameter

using Test

const server = "http://127.0.0.1:8081"

function runtests()
    @info("PetApi")
    client = Client(server)
    api = DeepClient.PetApi(client)
    unsold = FindPetsByStatusStatusParameter("key", ["available", "pending"])
    resp, http_resp = find_pets_by_status(api, unsold)
    res = resp.result
    @test res.name == "key"
    @test res.statuses == ["available", "pending"]
    @test http_resp.status == 200
end

end # module DeepObjectClientTest
