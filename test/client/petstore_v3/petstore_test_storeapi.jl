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
    inventory, http_resp = get_inventory(api)
    @test http_resp.status == 200
    @test isa(inventory, Dict{String,Int64})
    @test !isempty(inventory)

    @info("StoreApi - place_order")
    @test_throws OpenAPI.ValidationException Order(; id=5, petId=10, quantity=2, shipDate=DateTime(2017, 03, 12), status="invalid_status", complete=false)
    order = Order(; id=5, petId=10, quantity=2, shipDate=ZonedDateTime(DateTime(2017, 03, 12), localzone()), status="placed", complete=false)
    neworder, http_resp = place_order(api, order)
    @test http_resp.status == 200
    @test neworder.id == 5

    @info("StoreApi - get_order_by_id")
    @test_throws OpenAPI.ValidationException get_order_by_id(api, Int64(0))
    order, http_resp = get_order_by_id(api, Int64(5))
    @test http_resp.status == 200
    @test isa(order, Order)
    @test order.id == 5
    @test isa(order.shipDate, ZonedDateTime)

    @info("StoreApi - get_order_by_id (async)")
    response_channel = Channel{Order}(1)
    @test_throws OpenAPI.ValidationException get_order_by_id(api, response_channel, Int64(0))
    @sync begin
        @async begin
            api_return, http_resp = get_order_by_id(api, response_channel, Int64(5))
            @test (200 <= http_resp.status <= 206)
            @test api_return === response_channel
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

    # open a new channel to use
    response_channel = Channel{Order}(1)
    try
        resp, http_resp = get_order_by_id(api, response_channel, Int64(5))
        @test (200 <= http_resp.status <= 206)
    catch ex
        @test isa(ex, OpenAPI.InvocationException)
    end

    @info("StoreApi - delete_order")
    api_return, http_resp = delete_order(api, "5")
    @test api_return === nothing
    @test http_resp.status == 200

    nothing
end

end # module TestStoreApi
