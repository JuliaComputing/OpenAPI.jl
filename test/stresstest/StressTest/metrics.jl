"""
Metrics collection and reporting for stress tests.
"""

using Statistics
using Printf

"""
    StressMetrics

Container for collecting metrics during stress tests.

# Fields
- `request_times::Vector{Float64}` - Response time for each request (in seconds)
- `error_count::Int` - Total number of failed requests
- `error_types::Dict{String,Int}` - Count of each error type
- `start_time::Float64` - Test start time (from time())
- `end_time::Float64` - Test end time (from time())
"""
mutable struct StressMetrics
    request_times::Vector{Float64}
    error_count::Int
    error_types::Dict{String,Int}
    start_time::Float64
    end_time::Float64

    function StressMetrics()
        return new(Float64[], 0, Dict{String,Int}(), 0.0, 0.0)
    end
end

"""
    record_success(metrics::StressMetrics, duration::Float64)

Record a successful request with the given duration.

# Arguments
- `metrics::StressMetrics` - Metrics container
- `duration::Float64` - Request duration in seconds
"""
function record_success(metrics::StressMetrics, duration::Float64)
    push!(metrics.request_times, duration)
end

"""
    record_error(metrics::StressMetrics, error_type::String)

Record a failed request with the given error type.

# Arguments
- `metrics::StressMetrics` - Metrics container
- `error_type::String` - Type or description of the error
"""
function record_error(metrics::StressMetrics, error_type::String)
    metrics.error_count += 1
    metrics.error_types[error_type] = get(metrics.error_types, error_type, 0) + 1
end

"""
    calculate_percentile(times::Vector{Float64}, p::Float64)::Float64

Calculate the p-th percentile of the given times.

# Arguments
- `times::Vector{Float64}` - Vector of times (in seconds)
- `p::Float64` - Percentile (0-100)

# Returns
The p-th percentile value in seconds, or 0.0 if no data
"""
function calculate_percentile(times::Vector{Float64}, p::Float64)::Float64
    if isempty(times)
        return 0.0
    end

    sorted_times = sort(times)
    index = ceil(Int, length(sorted_times) * p / 100)
    index = max(1, min(index, length(sorted_times)))
    return sorted_times[index]
end

"""
    get_total_requests(metrics::StressMetrics)::Int

Get the total number of requests (successful + failed).
"""
function get_total_requests(metrics::StressMetrics)::Int
    return length(metrics.request_times) + metrics.error_count
end

"""
    get_success_count(metrics::StressMetrics)::Int

Get the number of successful requests.
"""
function get_success_count(metrics::StressMetrics)::Int
    return length(metrics.request_times)
end

"""
    get_success_rate(metrics::StressMetrics)::Float64

Get the success rate as a percentage (0-100).
"""
function get_success_rate(metrics::StressMetrics)::Float64
    total = get_total_requests(metrics)
    if total == 0
        return 0.0
    end
    return 100.0 * get_success_count(metrics) / total
end

"""
    get_error_rate(metrics::StressMetrics)::Float64

Get the error rate as a percentage (0-100).
"""
function get_error_rate(metrics::StressMetrics)::Float64
    return 100.0 - get_success_rate(metrics)
end

"""
    get_throughput(metrics::StressMetrics)::Float64

Get the throughput in requests per second.
"""
function get_throughput(metrics::StressMetrics)::Float64
    if metrics.start_time == 0.0 || metrics.end_time == 0.0
        return 0.0
    end

    duration = metrics.end_time - metrics.start_time
    if duration <= 0.0
        return 0.0
    end

    return get_total_requests(metrics) / duration
end

"""
    get_min_latency(metrics::StressMetrics)::Float64

Get the minimum request latency in seconds.
"""
function get_min_latency(metrics::StressMetrics)::Float64
    if isempty(metrics.request_times)
        return 0.0
    end
    return minimum(metrics.request_times)
end

"""
    get_max_latency(metrics::StressMetrics)::Float64

Get the maximum request latency in seconds.
"""
function get_max_latency(metrics::StressMetrics)::Float64
    if isempty(metrics.request_times)
        return 0.0
    end
    return maximum(metrics.request_times)
end

"""
    get_mean_latency(metrics::StressMetrics)::Float64

Get the mean request latency in seconds.
"""
function get_mean_latency(metrics::StressMetrics)::Float64
    if isempty(metrics.request_times)
        return 0.0
    end
    return mean(metrics.request_times)
end

"""
    get_median_latency(metrics::StressMetrics)::Float64

Get the median request latency in seconds.
"""
function get_median_latency(metrics::StressMetrics)::Float64
    if isempty(metrics.request_times)
        return 0.0
    end
    return median(metrics.request_times)
end

"""
    report_metrics(metrics::StressMetrics, endpoint::String, payload_size::Union{Int,Nothing}=nothing)

Print a formatted report of the collected metrics.

# Arguments
- `metrics::StressMetrics` - Metrics container
- `endpoint::String` - The endpoint that was tested (e.g., "GET /echo")
- `payload_size::Union{Int,Nothing}` - Payload size in bytes (optional, for POST requests)
"""
function report_metrics(metrics::StressMetrics, endpoint::String, payload_size::Union{Int,Nothing}=nothing)
    println("\n" * "="^60)
    println("$endpoint Results")
    if payload_size !== nothing
        println("Payload Size: $(format_bytes(payload_size))")
    end
    println("="^60)

    total = get_total_requests(metrics)
    success = get_success_count(metrics)
    success_rate = get_success_rate(metrics)
    error_rate = get_error_rate(metrics)

    println("  Total Requests: $(format_number(total))")
    println("  Successful: $(format_number(success)) ($(format_percent(success_rate))%)")
    println("  Failed: $(metrics.error_count) ($(format_percent(error_rate))%)")

    if metrics.error_count > 0
        println("\n  Error Types:")
        for (error_type, count) in sort(collect(metrics.error_types), by=x -> -x[2])
            percent = 100.0 * count / metrics.error_count
            println("    $error_type: $count ($(format_percent(percent))%)")
        end
    end

    throughput = get_throughput(metrics)
    println("\n  Throughput: $(format_number(throughput)) req/s")

    if !isempty(metrics.request_times)
        println("\n  Latency:")
        println("    Min: $(format_latency(get_min_latency(metrics)))")
        println("    Mean: $(format_latency(get_mean_latency(metrics)))")
        println("    Median: $(format_latency(get_median_latency(metrics)))")
        println("    Max: $(format_latency(get_max_latency(metrics)))")
        println("    P95: $(format_latency(calculate_percentile(metrics.request_times, 95.0)))")
        println("    P99: $(format_latency(calculate_percentile(metrics.request_times, 99.0)))")
    end

    if metrics.start_time > 0.0 && metrics.end_time > 0.0
        duration = metrics.end_time - metrics.start_time
        println("\n  Duration: $(format_number(duration))s")
    end
    println()
end

# Formatting helper functions

"""
    format_number(n::Union{Int,Float64})::String

Format a number with thousand separators.
"""
function format_number(n::Union{Int,Float64})::String
    if n isa Int
        # Format integer with commas as thousand separators
        s = string(n)
        parts = []
        for (i, c) in enumerate(reverse(s))
            if i > 1 && (i - 1) % 3 == 0
                pushfirst!(parts, ",")
            end
            pushfirst!(parts, c)
        end
        return join(parts)
    else
        return @sprintf("%.1f", n)
    end
end

"""
    format_percent(p::Float64)::String

Format a percentage with one decimal place.
"""
function format_percent(p::Float64)::String
    return @sprintf("%.1f", p)
end

"""
    format_latency(seconds::Float64)::String

Format latency in appropriate units (ms or seconds).
"""
function format_latency(seconds::Float64)::String
    if seconds < 0.001
        return @sprintf("%.2fμs", seconds * 1e6)
    elseif seconds < 1.0
        return @sprintf("%.2fms", seconds * 1000)
    else
        return @sprintf("%.2fs", seconds)
    end
end

"""
    format_bytes(bytes::Int)::String

Format bytes in appropriate units (B, KB, MB, GB).
"""
function format_bytes(bytes::Int)::String
    if bytes < 1024
        return "$(bytes)B"
    elseif bytes < 1024 * 1024
        return @sprintf("%.1fKB", bytes / 1024)
    elseif bytes < 1024 * 1024 * 1024
        return @sprintf("%.1fMB", bytes / (1024 * 1024))
    else
        return @sprintf("%.1fGB", bytes / (1024 * 1024 * 1024))
    end
end
