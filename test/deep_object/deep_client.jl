module DeepClientTest

include("DeepClient/src/DeepClient.jl")
using .DeepClient
using .DeepClient.OpenAPI.Clients: Client
using .DeepClient: FindPetsByStatusStatusParameter

using Test

const server = "http://127.0.0.1:8081"

function runtests(httplib::Symbol)
    @info("DeepObject tests ($httplib backend)")
    client = Client(server; httplib=httplib)
    api = DeepClient.PetApi(client)
    unsold = FindPetsByStatusStatusParameter("key", ["available", "pending"])
    resp, http_resp = find_pets_by_status(api, unsold)
    @debug("deep object response", resp, http_resp)
    res = resp.result
    @test res.name == "key"
    @test res.statuses == ["available", "pending"]
    @test http_resp.status == 200
end

end # module DeepObjectClientTest
