"""
Stress test execution functions for testing the OpenAPI client.
"""

"""
    StressTestConfig

Configuration for stress tests.

# Fields
- `duration::Int` - Test duration in seconds
- `concurrency::Int` - Number of concurrent tasks
- `payload_size::Int` - POST payload size in bytes
- `httplib::Symbol` - HTTP backend to use (:http or :downloads)
- `target_url::String` - Base URL of the echo server
"""
mutable struct StressTestConfig
    duration::Int
    concurrency::Int
    payload_size::Int
    httplib::Symbol
    target_url::String

    function StressTestConfig(;
        duration=30,
        concurrency=100,
        payload_size=1024,
        httplib=:http,
        target_url="http://127.0.0.1:8082",
    )
        return new(duration, concurrency, payload_size, httplib, target_url)
    end
end

function generate_payload(size::Int)
    data = "x" ^ max(1, size)
    return Main.StressTestClient.EchoPostRequest(; data = data)
end

"""
    run_get_stress_test(api::DefaultApi, config::StressTestConfig, metrics::StressMetrics)

Run a GET stress test for the specified duration and concurrency.

# Arguments
- `api::DefaultApi` - API instance to use
- `config::StressTestConfig` - Test configuration
- `metrics::StressMetrics` - Metrics container to record results
"""
function run_get_stress_test(api::Main.StressTestClient.DefaultApi, config::StressTestConfig, metrics::StressMetrics)
    @info("Starting GET stress test")

    metrics.start_time = time()

    @sync begin
        for task_idx in 1:config.concurrency
            @async begin
                task_start = time()
                local requests_made = 0

                while time() - task_start < config.duration
                    try
                        t0 = time()
                        result, resp = Main.StressTestClient.echo_get(api)
                        duration = time() - t0

                        if resp.status == 200
                            record_success(metrics, duration)
                        else
                            record_error(metrics, "HTTP-$(resp.status)")
                        end

                        requests_made += 1
                    catch ex
                        error_type = string(typeof(ex))
                        # Remove module prefix for cleaner output
                        error_type = split(error_type, ".")[end]
                        record_error(metrics, error_type)
                    end
                end
            end
        end
    end

    metrics.end_time = time()
end

"""
    run_post_stress_test(api::DefaultApi, config::StressTestConfig, metrics::StressMetrics)

Run a POST stress test for the specified duration and concurrency.

# Arguments
- `api::DefaultApi` - API instance to use
- `config::StressTestConfig` - Test configuration
- `metrics::StressMetrics` - Metrics container to record results
"""
function run_post_stress_test(api::Main.StressTestClient.DefaultApi, config::StressTestConfig, metrics::StressMetrics)
    @info("Starting POST stress test")
    payload = generate_payload(config.payload_size)
    metrics.start_time = time()

    @sync begin
        for task_idx in 1:config.concurrency
            @async begin
                task_start = time()
                local requests_made = 0

                while time() - task_start < config.duration
                    try
                        t0 = time()
                        result, resp = Main.StressTestClient.echo_post(api, payload)
                        duration = time() - t0

                        if resp.status == 200
                            record_success(metrics, duration)
                        else
                            record_error(metrics, "HTTP-$(resp.status)")
                        end

                        requests_made += 1
                    catch ex
                        error_type = string(typeof(ex))
                        # Remove module prefix for cleaner output
                        error_type = split(error_type, ".")[end]
                        record_error(metrics, error_type)
                    end
                end
            end
        end
    end

    metrics.end_time = time()
end
