module StressTest

using JSON
using Statistics
using Printf

# Include submodules in correct dependency order
include("metrics.jl")      # Independent, must come first
include("execution.jl")    # Depends on metrics.jl

# Re-export all public functions and types
export StressMetrics,
       record_success, record_error,
       report_metrics,
       calculate_percentile,
       get_total_requests, get_success_count,
       get_success_rate, get_error_rate, get_throughput,
       get_min_latency, get_max_latency,
       get_mean_latency, get_median_latency,
       StressTestConfig,
       run_get_stress_test, run_post_stress_test,
       generate_payload

end # module
