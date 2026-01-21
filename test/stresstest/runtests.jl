"""
Stress tests for OpenAPI.jl client testing.

Environment Variables:
    STRESS_DURATION - Test duration in seconds (default: 10)
    STRESS_CONCURRENCY - Number of concurrent tasks (default: 10)
    STRESS_PAYLOAD_SIZE - POST payload size in bytes (default: 1024)
    STRESS_HTTPLIB - HTTP backend to use, :http or :downloads (default: :http)

Example:
    STRESS_DURATION=30 STRESS_CONCURRENCY=10 julia --project=.. runtests.jl
"""

using Test
using OpenAPI
using OpenAPI.Clients
using HTTP

include("../testutils.jl")
include("StressTestClient/src/StressTestClient.jl")
using .StressTestClient
include("StressTest/StressTest.jl")
using .StressTest

const TEST_PORT = 8082
const TEST_SERVER_SCRIPT = abspath(joinpath(@__DIR__, "stresstest_server.jl"))

"""
Parse configuration from environment variables with defaults.
"""
function get_config()
    duration = parse(Int, get(ENV, "STRESS_DURATION", "30"))
    concurrency = parse(Int, get(ENV, "STRESS_CONCURRENCY", "10"))
    payload_size = parse(Int, get(ENV, "STRESS_PAYLOAD_SIZE", "1024"))

    httplib_str = get(ENV, "STRESS_HTTPLIB", "http")
    httplib = Symbol(httplib_str)
    if !in(httplib, (:http, :downloads))
        @warn("Invalid STRESS_HTTPLIB '$httplib_str', using :http")
        httplib = :http
    end

    return StressTestConfig(
        duration=duration,
        concurrency=concurrency,
        payload_size=payload_size,
        httplib=httplib,
    )
end

function main()
    config = get_config()

    @info("Starting stress test",
        server_port=TEST_PORT,
        duration = config.duration,
        concurrency = config.concurrency,
        http_backend = config.httplib,

    )
    proc, iob = run_server(TEST_SERVER_SCRIPT)

    try
        if !wait_server(TEST_PORT)
            @error("Server failed to start")
            return false
        end

        client = OpenAPI.Clients.Client(config.target_url; httplib=config.httplib)
        api = StressTestClient.DefaultApi(client)

        get_metrics = StressMetrics()
        run_get_stress_test(api, config, get_metrics)
        report_metrics(get_metrics, "GET /echo")

        post_metrics = StressMetrics()
        run_post_stress_test(api, config, post_metrics)
        report_metrics(post_metrics, "POST /echo", config.payload_size)

        return true
    finally
        @info("Stopping server")
        stop_server(TEST_PORT, proc, iob)
    end
end

@testset "Stress Tests" begin
    success = main()
    @test success
end
