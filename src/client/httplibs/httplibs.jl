# =============================================================================
# HTTP Backend Interface Contract
# =============================================================================
#
# Each HTTP backend implementation must provide the following functions:
#
# 1. Request Preparation (via Val dispatch)
#    prep_args(::Val{:backend_symbol}, ctx::Ctx) -> (body, kwargs)
#
#    Prepares request body and HTTP library-specific options from the context.
#    - Handles content-type detection and setting
#    - Processes form data and file uploads
#    - Converts body to appropriate format (JSON, form-encoded, etc.)
#    - Returns tuple of (body, kwargs) for the HTTP library
#
# 2. Request Execution (via Val dispatch)
#    do_request(::Val{:backend_symbol}, ctx::Ctx, resource_path::String,
#               body, output, kwargs, stream::Bool; stream_to::Union{Channel,Nothing})
#               -> (response, output)
#
#    Executes the HTTP request using the backend library.
#    - Performs synchronous or streaming request based on `stream` flag
#    - Handles task management for streaming responses
#    - Returns tuple of (response, output) or (error, output) on failure
#
# 3. Response Header Access (via Type dispatch)
#    get_response_header(resp::BackendResponse, name::AbstractString,
#                        defaultval::AbstractString) -> String
#
#    Retrieves a header value from the backend-specific response object.
#    Case-insensitive header name matching required.
#
# 4. Error Information Extraction (via Type dispatch)
#    get_message(error::BackendError) -> String
#    get_response(error::BackendError) -> Union{Nothing, BackendResponse}
#    get_status(error::BackendError) -> Int
#
#    Extracts error information from backend-specific error objects.
#    - get_message: Human-readable error description
#    - get_response: Associated response object (if available)
#    - get_status: HTTP status code (0 if no response available)
#
# 5. Response Property Access (via Type dispatch, optional)
#    get_response_property(raw::BackendResponse, name::Symbol) -> Any
#
#    Provides access to backend-specific response properties.
#    Only needed if backend response type doesn't directly support
#    required properties (status, message, headers).
#
# =============================================================================
# Available Backend Implementations
# =============================================================================
#
# :downloads (OpenAPI.HTTPLib.Downloads) - Uses Downloads.jl from Julia stdlib
# :http (OpenAPI.HTTPLib.HTTP) - Uses HTTP.jl from JuliaWeb ecosystem
#
# =============================================================================

include("juliaweb_http.jl")
include("julialang_downloads.jl")