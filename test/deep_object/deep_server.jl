module DeepServerTest
include("DeepServer/src/DeepServer.jl")
using .DeepServer
using HTTP
using .DeepServer: register, FindPetsByStatus200Response

const server = Ref{Any}(nothing)

function find_pets_by_status(::HTTP.Messages.Request, param::DeepServer.FindPetsByStatusStatusParameter)
    return FindPetsByStatus200Response(param)
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
        @info "Running deepserver"
        router = HTTP.Router()
        HTTP.register!(router, "GET", "/stop", stop)
        HTTP.register!(router, "GET", "/ping", ping)
        router = register(router, @__MODULE__)
        server[] = HTTP.serve!(router, port)
        @info "wait deepserver"
        wait(server[])
    catch ex
        @error("Server error", exception=(ex, catch_backtrace()))
    end
end

end # module DeepObjectClientTest
DeepServerTest.run_server()
