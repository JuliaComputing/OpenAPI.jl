module TestStoreApi

using ..PetStoreClient
using Test
using Dates
using TimeZones
using OpenAPI
using OpenAPI.Clients
import OpenAPI.Clients: Client

function test(uri)
    @info("StoreApi")
    client = Client(uri)
    api = StoreApi(client)

    @info("StoreApi - getInventory")
    inventory = getInventory(api)
    @test isa(inventory, Dict{String,Int64})
    @test !isempty(inventory)

    @info("StoreApi - placeOrder")
    @test_throws OpenAPI.ValidationException Order(; id=5, petId=10, quantity=2, shipDate=DateTime(2017, 03, 12), status="invalid_status", complete=false)
    order = Order(; id=5, petId=10, quantity=2, shipDate=ZonedDateTime(DateTime(2017, 03, 12), localzone()), status="placed", complete=false)
    neworder = placeOrder(api, order)
    @test neworder.id == 5

    @info("StoreApi - getOrderById")
    @test_throws OpenAPI.ValidationException getOrderById(api, 0)
    order = getOrderById(api, 5)
    @test isa(order, Order)
    @test order.id == 5
    @test isa(order.shipDate, ZonedDateTime)

    @info("StoreApi - getOrderById (async)")
    response_channel = Channel{Order}(1)
    @test_throws OpenAPI.ValidationException getOrderById(api, response_channel, 0)
    @sync begin
        @async begin
            resp = getOrderById(api, response_channel, 5)
            @test (200 <= resp.status <= 206)
        end
        @async begin
            order = take!(response_channel)
            @test isa(order, Order)
            @test order.id == 5
        end
    end

    # a closed channel is equivalent of cancellation of the call,
    # no error should be thrown, but response can be nothing if call was interrupted immediately
    @test !isopen(response_channel)
    resp = getOrderById(api, response_channel, 5)
    @test (resp === nothing) || (200 <= resp.status <= 206)

    @info("StoreApi - deleteOrder")
    @test deleteOrder(api, 5) === nothing

    nothing
end

end # module TestStoreApi
