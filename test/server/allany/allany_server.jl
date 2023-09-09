module AllAnyServerImpl

using HTTP

include("AllAnyServer/src/AllAnyServer.jl")

using .AllAnyServer

const server = Ref{Any}(nothing)

"""
echo_arrays_post

*invocation:* POST /echo_arrays
"""
function echo_arrays_post(req::HTTP.Request, type_with_all_array_types::AllAnyServer.TypeWithAllArrayTypes;) :: AllAnyServer.TypeWithAllArrayTypes
    return type_with_all_array_types
end

"""
echo_anyof_base_type_post

*invocation:* POST /echo_anyof_base_type
"""
function echo_anyof_base_type_post(req::HTTP.Request, any_of_base_type::AllAnyServer.AnyOfBaseType;) :: AllAnyServer.AnyOfBaseType
    return any_of_base_type
end

"""
echo_oneof_base_type_post

*invocation:* POST /echo_oneof_base_type
"""
function echo_oneof_base_type_post(req::HTTP.Request, one_of_base_type::AllAnyServer.OneOfBaseType;) :: AllAnyServer.OneOfBaseType
    return one_of_base_type
end

"""
echo_anyof_mapped_pets_post

*invocation:* POST /echo_anyof_mapped_pets
"""
function echo_anyof_mapped_pets_post(req::HTTP.Request, any_of_mapped_pets::AllAnyServer.AnyOfMappedPets,) :: AllAnyServer.AnyOfMappedPets
    return any_of_mapped_pets
end

"""
echo_anyof_pets_post

*invocation:* POST /echo_anyof_pets
"""
function echo_anyof_pets_post(req::HTTP.Request, any_of_pets::AllAnyServer.AnyOfPets,) :: AllAnyServer.AnyOfPets
    return any_of_pets
end

"""
echo_oneof_mapped_pets_post

*invocation:* POST /echo_oneof_mapped_pets
"""
function echo_oneof_mapped_pets_post(req::HTTP.Request, one_of_mapped_pets::AllAnyServer.OneOfMappedPets,) :: AllAnyServer.OneOfMappedPets
    return one_of_mapped_pets
end

"""
echo_oneof_pets_post

*invocation:* POST /echo_oneof_pets
"""
function echo_oneof_pets_post(req::HTTP.Request, one_of_pets::AllAnyServer.OneOfPets,) :: AllAnyServer.OneOfPets
    return one_of_pets
end

function stop(::HTTP.Request)
    HTTP.close(server[])
    return HTTP.Response(200, "")
end

function ping(::HTTP.Request)
    return HTTP.Response(200, "")
end

function run_server(port=8081)
    try
        router = HTTP.Router()
        router = AllAnyServer.register(router, @__MODULE__)
        HTTP.register!(router, "GET", "/stop", stop)
        HTTP.register!(router, "GET", "/ping", ping)
        server[] = HTTP.serve!(router, port)
        wait(server[])
    catch ex
        @error("Server error", exception=(ex, catch_backtrace()))
    end
end

end # module AllAnyServerImpl

AllAnyServerImpl.run_server()