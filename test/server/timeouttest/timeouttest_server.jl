module TimeoutTestServerImpl

using HTTP
using OpenAPI

include("TimeoutTestServer/src/TimeoutTestServer.jl")

using .TimeoutTestServer

const server = Ref{Any}(nothing)

"""
delayresponse_get

*invocation:* GET /delayresponse
"""
function delayresponse_get(request::HTTP.Request)
    delay_seconds = parse(Int, HTTP.URIs.queryparams(HTTP.URIs.parse_uri_reference(request.target))["delay_seconds"])
    sleep(delay_seconds)
    return HTTP.Response(200, OpenAPI.Clients.to_json(TimeoutTestServer.DelayresponseGet200Response(string(delay_seconds))))
end

function stop(::HTTP.Request)
    HTTP.close(server[])
    return HTTP.Response(200, "")
end

function ping(::HTTP.Request)
    return HTTP.Response(200, "")
end

function longpollstream(stream::HTTP.Stream)
    request::HTTP.Request = stream.message

    if startswith(request.target, "/longpollstream")
        HTTP.setheader(stream, "Content-Type" => "application/json")
        delay_seconds = parse(Int, HTTP.URIs.queryparams(HTTP.URIs.parse_uri_reference(request.target))["delay_seconds"])
        while true
            write(stream, OpenAPI.Clients.to_json(TimeoutTestServer.DelayresponseGet200Response(string(delay_seconds))))
            write(stream, "\n")
            sleep(delay_seconds)
        end
    end
    return nothing
end

function run_server(port=8081)
    try
        router = HTTP.Router()
        HTTP.register!(router, "/delayresponse", HTTP.streamhandler(delayresponse_get))
        HTTP.register!(router, "/longpollstream", longpollstream)
        HTTP.register!(router, "/stop", HTTP.streamhandler(stop))
        HTTP.register!(router, "/ping", HTTP.streamhandler(ping))
        server[] = HTTP.serve!(router, port; stream=true)
        wait(server[])
    catch ex
        @error("Server error", exception=(ex, catch_backtrace()))
    end
end

end # module TimeoutTestServerImpl

TimeoutTestServerImpl.run_server()