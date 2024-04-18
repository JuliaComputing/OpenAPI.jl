module TimeoutTestServerImpl

using HTTP

include("TimeoutTestServer/src/TimeoutTestServer.jl")

using .TimeoutTestServer

const server = Ref{Any}(nothing)

"""
delayresponse_get

*invocation:* GET /delayresponse
"""
function delayresponse_get(req::HTTP.Request, delay_seconds::Int64;) :: TimeoutTestServer.DelayresponseGet200Response
    sleep(delay_seconds)
    return TimeoutTestServer.DelayresponseGet200Response(string(delay_seconds))
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
        router = TimeoutTestServer.register(router, @__MODULE__)
        HTTP.register!(router, "GET", "/stop", stop)
        HTTP.register!(router, "GET", "/ping", ping)
        server[] = HTTP.serve!(router, port)
        wait(server[])
    catch ex
        @error("Server error", exception=(ex, catch_backtrace()))
    end
end

end # module TimeoutTestServerImpl

TimeoutTestServerImpl.run_server()