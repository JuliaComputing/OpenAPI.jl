module PetStoreV3Server

using HTTP

include("petstore/src/PetStoreServer.jl")

using .PetStoreServer

const server = Ref{Any}(nothing)
const pets = Vector{Pet}()
const orders = Vector{Order}()
const users = Vector{User}()
const PRESET_TEST_USER = "user1"

function add_pet(req::HTTP.Request, pet::Pet;)
    push!(pets, pet)
    return nothing
end

function delete_pet(req::HTTP.Request, pet_id::Int64; api_key=nothing,)
    filter!(x->x.id != pet_id, pets)
    return nothing
end

function find_pets_by_status(req::HTTP.Request, status::Vector{String};)
    return filter(x->x.status == status, pets)
end

function find_pets_by_tags(req::HTTP.Request, tags::Vector{String};)
    return filter(x->!isempty(intersect(Set(x.tags), Set(tags))), pets)
end

function get_pet_by_id(req::HTTP.Request, pet_id::Int64;)
    pet = findfirst(x->x.id == pet_id, pets)
    if pet === nothing
        return HTTP.Response(404, "Pet not found")
    else
        return pets[pet]
    end
end

function update_pet(req::HTTP.Request, pet::Pet;)
    filter!(x->x.id != pet.id, pets)
    push!(pets, pet)
    return nothing
end

function update_pet_with_form(req::HTTP.Request, pet_id::Int64; name=nothing, status=nothing,)
    for pet in pets
        if pet.id == pet_id
            if !isnothing(name)
                pet.name = name
            end
            if !isnothing(status)
                pet.status = status
            end
        end
    end
    return nothing
end

function upload_file(req::HTTP.Request, pet_id::Int64; additional_metadata=nothing, file=nothing,)
    return ApiResponse(; code=1, type="pet", message="file uploaded", )
end

function delete_order(req::HTTP.Request, order_id::String;)
    filter!(x->x.id != order_id, orders)
    return nothing
end

function get_inventory(req::HTTP.Request;)
    return Dict{String, Int64}(
        "additionalProp1" => 0,
        "additionalProp2" => 0,
        "additionalProp3" => 0,
    )
end

function get_order_by_id(req::HTTP.Request, order_id::Int64;)
    order = findfirst(x->x.id == order_id, orders)
    if order === nothing
        return HTTP.Response(404, "Order not found")
    else
        return orders[order]
    end
end

function place_order(req::HTTP.Request, order::Order;)
    if isnothing(order.id)
        max_OrderId = isempty(orders) ? 0 : maximum(x->x.id, orders)
        order.id = max_OrderId + 1
    end
    push!(orders, order)
    return order
end

function create_user(req::HTTP.Request, user::User;)
    push!(users, user)
    return nothing
end

function create_users_with_array_input(req::HTTP.Request, user::Vector{User};)
    append!(users, user)
    return nothing
end

function create_users_with_list_input(req::HTTP.Request, user::Vector{User};)
    append!(users, user)
    return nothing
end

function delete_user(req::HTTP.Request, username::String;)
    filter!(x->x.username != username, users)
    return nothing
end

function get_user_by_name(req::HTTP.Request, username::String;)
    # user = findfirst(x->x.username == username, users)
    # if user === nothing
    #     return HTTP.Response(404, "User not found")
    # else
    #     return user
    # end
    if username == PRESET_TEST_USER
        return User(; id=1, username=PRESET_TEST_USER, firstName="John", lastName="Doe", email="jondoe@test.com", phone="1234567890", userStatus=1, )
    else
        return HTTP.Response(404, "User not found")
    end
end

function login_user(req::HTTP.Request, username::String, password::String;)
    return "logged in user session: test"
end

function logout_user(req::HTTP.Request;)
    return nothing
end

function update_user(req::HTTP.Request, username::String, user::User;)
    filter!(x->x.username != username, users)
    push!(users, user)
    return nothing
end

function stop(::HTTP.Request)
    HTTP.close(server[])
    return HTTP.Response(200, "")
end

function run_server(port=8081)
    router = HTTP.Router()
    router = PetStoreServer.register(router, @__MODULE__; path_prefix="/v3")
    HTTP.register!(router, "GET", "/stop", stop)
    server[] = HTTP.serve!(router, port)
    wait(server[])
end

end # module PetStoreV3Server

PetStoreV3Server.run_server()