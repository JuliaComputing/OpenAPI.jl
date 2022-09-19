module PetStoreV3Server

using HTTP

include("petstore/src/PetStoreServer.jl")

using .PetStoreServer

const server = Ref{Any}(nothing)
const pets = Vector{Pet}()
const orders = Vector{Order}()
const users = Vector{User}()
const PRESET_TEST_USER = "user1"

"""
**addPet**
- *invocation:* POST /pet
- *signature:* addPet(req::HTTP.Request, in_Pet::Pet;) -> Nothing
"""
function addPet(req::HTTP.Request, in_Pet::Pet;)
    push!(pets, in_Pet)
    return nothing
end

"""
- **deletePet**
    - *invocation:* DELETE /pet/{petId}
    - *signature:* deletePet(req::HTTP.Request, in_petId::Int64; in_api_key=nothing,) -> Nothing
"""
function deletePet(req::HTTP.Request, in_petId::Int64; in_api_key=nothing,)
    filter!(x->x.id != in_petId, pets)
    return nothing
end

"""
- **findPetsByStatus**
    - *invocation:* GET /pet/findByStatus
    - *signature:* findPetsByStatus(req::HTTP.Request, in_status::Vector{String};) -> Vector{Pet}
"""
function findPetsByStatus(req::HTTP.Request, in_status::Vector{String};)
    return filter(x->x.status == in_status, pets)
end

"""
- **findPetsByTags**
    - *invocation:* GET /pet/findByTags
    - *signature:* findPetsByTags(req::HTTP.Request, in_tags::Vector{String};) -> Vector{Pet}
"""
function findPetsByTags(req::HTTP.Request, in_tags::Vector{String};)
    return filter(x->!isempty(intersect(Set(x.tags), Set(in_tags))), pets)
end

"""
- **getPetById**
    - *invocation:* GET /pet/{petId}
    - *signature:* getPetById(req::HTTP.Request, in_petId::Int64;) -> Pet
"""
function getPetById(req::HTTP.Request, in_petId::Int64;)
    pet = findfirst(x->x.id == in_petId, pets)
    if pet === nothing
        return HTTP.Response(404, "Pet not found")
    else
        return pets[pet]
    end
end

"""
- **updatePet**
    - *invocation:* PUT /pet
    - *signature:* updatePet(req::HTTP.Request, in_Pet::Pet;) -> Nothing
"""
function updatePet(req::HTTP.Request, in_Pet::Pet;)
    filter!(x->x.id != in_Pet.id, pets)
    push!(pets, in_Pet)
    return nothing
end

"""
- **updatePetWithForm**
    - *invocation:* POST /pet/{petId}
    - *signature:* updatePetWithForm(req::HTTP.Request, in_petId::Int64; in_name=nothing, in_status=nothing,) -> Nothing
"""
function updatePetWithForm(req::HTTP.Request, in_petId::Int64; in_name=nothing, in_status=nothing,)
    for pet in pets
        if pet.id == in_petId
            if !isnothing(in_name)
                pet.name = in_name
            end
            if !isnothing(in_status)
                pet.status = in_status
            end
        end
    end
    return nothing
end

"""
- **uploadFile**
    - *invocation:* POST /pet/{petId}/uploadImage
    - *signature:* uploadFile(req::HTTP.Request, in_petId::Int64; in_additionalMetadata=nothing, in_file=nothing,) -> ApiResponse
"""
function uploadFile(req::HTTP.Request, in_petId::Int64; in_additionalMetadata=nothing, in_file=nothing,)
    return ApiResponse(; code=1, type="pet", message="file uploaded", )
end

"""
- **deleteOrder**
    - *invocation:* DELETE /store/order/{orderId}
    - *signature:* deleteOrder(req::HTTP.Request, in_orderId::String;) -> Nothing
"""
function deleteOrder(req::HTTP.Request, in_orderId::String;)
    filter!(x->x.id != in_orderId, orders)
    return nothing
end

"""
- **getInventory**
    - *invocation:* GET /store/inventory
    - *signature:* getInventory(req::HTTP.Request;) -> Dict{String, Int64}
"""
function getInventory(req::HTTP.Request;)
    return Dict{String, Int64}(
        "additionalProp1" => 0,
        "additionalProp2" => 0,
        "additionalProp3" => 0,
    )
end

"""
- **getOrderById**
    - *invocation:* GET /store/order/{orderId}
    - *signature:* getOrderById(req::HTTP.Request, in_orderId::Int64;) -> Order
"""
function getOrderById(req::HTTP.Request, in_orderId::Int64;)
    order = findfirst(x->x.id == in_orderId, orders)
    if order === nothing
        return HTTP.Response(404, "Order not found")
    else
        return orders[order]
    end
end

"""
- **placeOrder**
    - *invocation:* POST /store/order
    - *signature:* placeOrder(req::HTTP.Request, in_Order::Order;) -> Order
"""
function placeOrder(req::HTTP.Request, in_Order::Order;)
    if isnothing(in_Order.id)
        max_OrderId = isempty(orders) ? 0 : maximum(x->x.id, orders)
        in_Order.id = max_OrderId + 1
    end
    push!(orders, in_Order)
    return in_Order
end

"""
- **createUser**
    - *invocation:* POST /user
    - *signature:* createUser(req::HTTP.Request, in_User::User;) -> Nothing
"""
function createUser(req::HTTP.Request, in_User::User;)
    push!(users, in_User)
    return nothing
end

"""
- **createUsersWithArrayInput**
    - *invocation:* POST /user/createWithArray
    - *signature:* createUsersWithArrayInput(req::HTTP.Request, in_User::Vector{User};) -> Nothing
"""
function createUsersWithArrayInput(req::HTTP.Request, in_User::Vector{User};)
    append!(users, in_User)
    return nothing
end

"""
- **createUsersWithListInput**
    - *invocation:* POST /user/createWithList
    - *signature:* createUsersWithListInput(req::HTTP.Request, in_User::Vector{User};) -> Nothing
"""
function createUsersWithListInput(req::HTTP.Request, in_User::Vector{User};)
    append!(users, in_User)
    return nothing
end

"""
- **deleteUser**
    - *invocation:* DELETE /user/{username}
    - *signature:* deleteUser(req::HTTP.Request, in_username::String;) -> Nothing
"""
function deleteUser(req::HTTP.Request, in_username::String;)
    filter!(x->x.username != in_username, users)
    return nothing
end

"""
- **getUserByName**
    - *invocation:* GET /user/{username}
    - *signature:* getUserByName(req::HTTP.Request, in_username::String;) -> User
"""
function getUserByName(req::HTTP.Request, in_username::String;)
    # user = findfirst(x->x.username == in_username, users)
    # if user === nothing
    #     return HTTP.Response(404, "User not found")
    # else
    #     return user
    # end
    if in_username == PRESET_TEST_USER
        return User(; id=1, username=PRESET_TEST_USER, firstName="John", lastName="Doe", email="jondoe@test.com", phone="1234567890", userStatus=1, )
    else
        return HTTP.Response(404, "User not found")
    end
end

"""
- **loginUser**
    - *invocation:* GET /user/login
    - *signature:* loginUser(req::HTTP.Request, in_username::String, in_password::String;) -> String
"""
function loginUser(req::HTTP.Request, in_username::String, in_password::String;)
    return "logged in user session: test"
end

"""
- **logoutUser**
    - *invocation:* GET /user/logout
    - *signature:* logoutUser(req::HTTP.Request;) -> Nothing
"""
function logoutUser(req::HTTP.Request;)
    return nothing
end

"""
- **updateUser**
    - *invocation:* PUT /user/{username}
    - *signature:* updateUser(req::HTTP.Request, in_username::String, in_User::User;) -> Nothing
"""
function updateUser(req::HTTP.Request, in_username::String, in_User::User;)
    filter!(x->x.username != in_username, users)
    push!(users, in_User)
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