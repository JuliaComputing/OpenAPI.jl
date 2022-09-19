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

    @info("StoreApi - get_inventory")
    inventory = get_inventory(api)
    @test isa(inventory, Dict{String,Int64})
    @test !isempty(inventory)

    @info("StoreApi - place_order")
    @test_throws OpenAPI.ValidationException Order(; id=5, petId=10, quantity=2, shipDate=DateTime(2017, 03, 12), status="invalid_status", complete=false)
    order = Order(; id=5, petId=10, quantity=2, shipDate=ZonedDateTime(DateTime(2017, 03, 12), localzone()), status="placed", complete=false)
    neworder = place_order(api, order)
    @test neworder.id == 5

    @info("StoreApi - get_order_by_id")
    @test_throws OpenAPI.ValidationException get_order_by_id(api, 0)
    order = get_order_by_id(api, 5)
    @test isa(order, Order)
    @test order.id == 5
    @test isa(order.shipDate, ZonedDateTime)

    @info("StoreApi - get_order_by_id (async)")
    response_channel = Channel{Order}(1)
    @test_throws OpenAPI.ValidationException get_order_by_id(api, response_channel, 0)
    @sync begin
        @async begin
            resp = get_order_by_id(api, response_channel, 5)
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
    resp = get_order_by_id(api, response_channel, 5)
    @test (resp === nothing) || (200 <= resp.status <= 206)

    @info("StoreApi - delete_order")
    @test delete_order(api, "5") === nothing

    nothing
end

end # module TestStoreApi
