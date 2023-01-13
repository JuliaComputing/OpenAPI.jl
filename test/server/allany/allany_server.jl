module AllAnyServerImpl

using HTTP

include("AllAnyServer/src/AllAnyServer.jl")

using .AllAnyServer

const server = Ref{Any}(nothing)

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