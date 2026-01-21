module StressTestServerImpl

using HTTP
using OpenAPI
using Dates
using Random
using JSON

const server = Ref{Any}(nothing)
const headers = ["Content-Type" => "application/json"]


"""
    echo_get(request::HTTP.Request)

Handler for GET /echo endpoint.
Returns a simple JSON response with timestamp and request info.
"""
function echo_get(request::HTTP.Request)
    timestamp = Dates.now(UTC)

    response_data = Dict(
        "timestamp" => string(timestamp),
        "message" => "Echo GET response",
    )

    return HTTP.Response(200, headers, JSON.json(response_data))
end

"""
    echo_post(request::HTTP.Request)

Handler for POST /echo endpoint.
Echoes back the request body with metadata.
"""
function echo_post(request::HTTP.Request)
    timestamp = Dates.now(UTC)
    request_body = String(request.body)
    request_data = JSON.parse(request_body)

    response_data = Dict(
        "timestamp" => string(timestamp),
        "data" => get(request_data, "data", ""),
    )

    response_json = JSON.json(response_data)

    return HTTP.Response(200, headers, response_json)
end

"""
    stop(::HTTP.Request)

Handler for GET /stop endpoint.
Gracefully shuts down the server.
"""
function stop(::HTTP.Request)
    try
        HTTP.close(server[])
    catch
        # Ignore errors during shutdown
    end
    return HTTP.Response(200, "")
end

"""
    ping(::HTTP.Request)

Handler for GET /ping endpoint.
Health check endpoint.
"""
function ping(::HTTP.Request)
    return HTTP.Response(200, "")
end

"""
    run_server(port=8082)

Start the echo server on the given port.
"""
function run_server(port=8082)
    try
        router = HTTP.Router()
        HTTP.register!(router, "GET", "/echo", echo_get)
        HTTP.register!(router, "POST", "/echo", echo_post)
        HTTP.register!(router, "GET", "/stop", stop)
        HTTP.register!(router, "GET", "/ping", ping)

        @info("Starting StressTest server on port $port")
        server[] = HTTP.serve!(router, "127.0.0.1", port; stream=false)
        wait(server[])
    catch ex
        @error("Server error", exception=(ex, catch_backtrace()))
    end
end

end # module StressTestServerImpl

# Start the server when this script is run directly
StressTestServerImpl.run_server()
