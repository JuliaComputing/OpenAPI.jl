abstract type AbstractChunkReader end
abstract type AbstractHTTPLibError end
const HTTPLibResponse = Union{HTTP.Response, Downloads.Response}
const HTTPLibError = Union{Downloads.RequestError, AbstractHTTPLibError}

# methods to get exception messages out of errors which could be surfaced either as request or response errors
get_message(::HTTPLibError) = ""
get_message(::HTTPLibResponse) = ""
get_response(::HTTPLibError) = nothing
get_status(::HTTPLibError) = 0

# collection formats (OpenAPI v2)
# TODO: OpenAPI v3 has style and explode options instead of collection formats, which are yet to be supported
# TODO: Examine whether multi is now supported
const COLL_MULTI = "multi"  # (legacy) aliased to CSV, as multi is not supported by Requests.jl (https://github.com/JuliaWeb/Requests.jl/issues/140)
const COLL_PIPES = "pipes"
const COLL_SSV = "ssv"
const COLL_TSV = "tsv"
const COLL_CSV = "csv"
const COLL_DLM = Dict{String,String}([COLL_PIPES=>"|", COLL_SSV=>" ", COLL_TSV=>"\t", COLL_CSV=>",", COLL_MULTI=>","])

const DEFAULT_TIMEOUT_SECS = 5*60
const DEFAULT_LONGPOLL_TIMEOUT_SECS = 15*60

const HTTPLib = (
    HTTP = :http,
    Downloads = :downloads
)

struct ApiException <: Exception
    status::Int
    reason::String
    resp::Union{Nothing, HTTPLibResponse}
    error::Union{Nothing, HTTPLibError}

    function ApiException(error::HTTPLibError; reason::String="")
        isempty(reason) && (reason = get_message(error))
        resp = get_response(error)
        status = get_status(error)
        new(status, reason, resp, error)
    end
end

"""
    ApiResponse

Represents the HTTP API response from the server. This is returned as the second return value from all API calls.

Properties available:
- `status`: the HTTP status code
- `message`: the HTTP status message
- `headers`: the HTTP headers
- `raw`: the raw response from the HTTP library used
"""
struct ApiResponse
    raw::HTTPLibResponse
end

get_response_property(raw::HTTPLibResponse, name::Symbol) = getproperty(raw, name)
function Base.getproperty(resp::ApiResponse, name::Symbol)
    raw = getfield(resp, :raw)
    if name in (:status, :message, :headers)
        return get_response_property(raw, name)
    else
        return getfield(resp, name)
    end
end


function get_api_return_type(return_types::Dict{Regex,Type}, ::Nothing, response_data::String)
    # this is the async case, where we do not have the response code yet
    # in such cases we look for the 200 response code
    return get_api_return_type(return_types, 200, response_data)
end
function get_api_return_type(return_types::Dict{Regex,Type}, response_code::Integer, response_data::String)
    default_response_code = 0
    for code in string.([response_code, default_response_code])
        for (re, rt) in return_types
            if match(re, code) !== nothing
                return rt
            end
        end
    end
    # if no specific return type was defined, we assume that:
    # - if response code is 2xx, then we make the method call return nothing
    # - otherwise we make it throw an ApiException
    return (200 <= response_code <=206) ? Nothing : nothing # first(return_types)[2]
end

function default_debug_hook(type, message)
    @info("OpenAPI HTTP transport", type, message)
end

"""
    Client(root::String;
        headers::Dict{String,String}=Dict{String,String}(),
        get_return_type::Function=get_api_return_type,
        long_polling_timeout::Int=DEFAULT_LONGPOLL_TIMEOUT_SECS,
        timeout::Int=DEFAULT_TIMEOUT_SECS,
        pre_request_hook::Function=noop_pre_request_hook,
        escape_path_params::Union{Nothing,Bool}=nothing,
        chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}=nothing,
        verbose::Union{Bool,Function}=false,
        httplib::Symbol=HTTPLib.Downloads,
    )

Create a new OpenAPI client context.

A client context holds common information to be used across APIs. It also holds a connection to the server and uses that across API calls.
The client context needs to be passed as the first parameter of all API calls.

Parameters:
- `root`: The root URL of the server. This is the base URL that will be used for all API calls.

Keyword parameters:
- `headers`: A dictionary of HTTP headers to be sent with all API calls.
- `get_return_type`: A function that is called to determine the return type of an API call. This function is called with the following parameters:
    - `return_types`: A dictionary of regular expressions and their corresponding return types. The regular expressions are matched against the HTTP status code of the response.
    - `response_code`: The HTTP status code of the response.
    - `response_data`: The response data as a string.
    The function should return the return type to be used for the API call.
- `long_polling_timeout`: The timeout in seconds for long polling requests. This is the time after which the request will be aborted if no data is received from the server.
- `timeout`: The timeout in seconds for all other requests. This is the time after which the request will be aborted if no data is received from the server.
- `pre_request_hook`: A function that is called before every API call. This function must provide two methods:
    - `pre_request_hook(ctx::Ctx)`: This method is called before every API call. It is passed the context object that will be used for the API call. The function should return the context object to be used for the API call.
    - `pre_request_hook(resource_path::AbstractString, body::Any, headers::Dict{String,String})`: This method is called before every API call. It is passed the resource path, request body and request headers that will be used for the API call. The function should return those after making any modifications to them.
- `escape_path_params`: Whether the path parameters should be escaped before being used in the URL. This is useful if the path parameters contain characters that are not allowed in URLs or contain path separators themselves.
- `chunk_reader_type`: The type of chunk reader to be used for streaming responses. This can be one of `LineChunkReader`, `JSONChunkReader` or `RFC7464ChunkReader`. If not specified, then the type is automatically determined based on the return type of the API call.
- `verbose`: Can be set either to a boolean or a function (function support depends on the HTTP library).
    - If set to true, then the client will log all HTTP requests and responses.
    - If set to a function (only supported with Downloads.jl backend), then that function will be called with the following parameters:
        - `type`: The type of message.
        - `message`: The message to be logged.
    - Note: When using HTTP.jl backend (`httplib=OpenAPI.HTTPLib.HTTP`), the `verbose` parameter must be a boolean.
- `httplib`: The HTTP client library to use for making requests. Can be `OpenAPI.HTTPLib.Downloads` (default) for Downloads.jl or `OpenAPI.HTTPLib.HTTP` for HTTP.jl.

"""
struct Client
    root::String
    headers::Dict{String,String}
    get_return_type::Function   # user provided hook to get return type from response data
    clntoptions::Dict{Symbol,Any}
    downloader::Union{Nothing,Downloader}
    timeout::Ref{Int}
    pre_request_hook::Function  # user provided hook to modify the request before it is sent
    escape_path_params::Union{Nothing,Bool}
    chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}
    long_polling_timeout::Int
    request_interrupt_supported::Bool
    httplib::Symbol  # which http implementation to use

    function Client(root::String;
            headers::Dict{String,String}=Dict{String,String}(),
            get_return_type::Function=get_api_return_type,
            long_polling_timeout::Int=DEFAULT_LONGPOLL_TIMEOUT_SECS,
            timeout::Int=DEFAULT_TIMEOUT_SECS,
            pre_request_hook::Function=noop_pre_request_hook,
            escape_path_params::Union{Nothing,Bool}=nothing,
            chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}=nothing,
            verbose::Union{Bool,Function}=false,
            httplib::Symbol=:http,
        )
        # Validate library choice
        if httplib ∉ values(HTTPLib)
            throw(ArgumentError("Invalid httplib: $httplib"))
        end

        clntoptions = Dict{Symbol,Any}(:throw=>false)
        if isa(verbose, Bool)
            clntoptions[:verbose] = verbose
        elseif isa(verbose, Function)
            if httplib === HTTPLib.HTTP
                throw(ArgumentError("With HTTP.jl, `verbose` can only be a boolean"))
            end
            clntoptions[:debug] = verbose
        end

        if httplib === HTTPLib.HTTP
            downloader = nothing
            interruptable = false
        else
            downloader = Downloads.Downloader()
            downloader.easy_hook = (easy, opts) -> begin
                Downloads.Curl.setopt(easy, LibCURL.CURLOPT_LOW_SPEED_TIME, long_polling_timeout)
                # disable ALPN to support servers that enable both HTTP/2 and HTTP/1.1 on same port
                Downloads.Curl.setopt(easy, LibCURL.CURLOPT_SSL_ENABLE_ALPN, 0)
            end

            interruptable = request_supports_interrupt()
        end
        new(root, headers, get_return_type, clntoptions, downloader, Ref{Int}(timeout), pre_request_hook, escape_path_params, chunk_reader_type, long_polling_timeout, interruptable, httplib)
    end
end

struct Ctx
    client::Client
    method::String
    return_types::Dict{Regex,Type}
    resource::String
    auth::Vector{String}

    path::Dict{String,String}
    query::Dict{String,String}
    header::Dict{String,String}
    form::Dict{String,String}
    file::Dict{String,String}
    body::Any
    timeout::Int
    curl_mime_upload::Ref{Any}
    pre_request_hook::Function
    escape_path_params::Bool
    chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}

    function Ctx(client::Client, method::String, return_types::Dict{Regex,Type}, resource::String, auth, body=nothing;
            timeout::Int=client.timeout[],
            pre_request_hook::Function=client.pre_request_hook,
            escape_path_params::Bool=something(client.escape_path_params, true),
            chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}=client.chunk_reader_type,
        )
        resource = client.root * resource
        headers = copy(client.headers)
        new(client, method, return_types, resource, auth, Dict{String,String}(), Dict{String,String}(), headers, Dict{String,String}(), Dict{String,String}(), body, timeout, Ref{Any}(nothing), pre_request_hook, escape_path_params, chunk_reader_type)
    end
end
