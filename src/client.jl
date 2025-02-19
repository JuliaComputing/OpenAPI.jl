module Clients

using Downloads
using URIs
using JSON
using MbedTLS
using Dates
using TimeZones
using LibCURL
using HTTP
using MIMEs

import Base: convert, show, summary, getproperty, setproperty!, iterate
import ..OpenAPI: APIModel, UnionAPIModel, OneOfAPIModel, AnyOfAPIModel, APIClientImpl, OpenAPIException, InvocationException, to_json, from_json, validate_property, property_type
import ..OpenAPI: str2zoneddatetime, str2datetime, str2date


abstract type AbstractChunkReader end

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

struct ApiException <: Exception
    status::Int
    reason::String
    resp::Downloads.Response
    error::Union{Nothing,Downloads.RequestError}

    function ApiException(error::Downloads.RequestError; reason::String="")
        isempty(reason) && (reason = error.message)
        isempty(reason) && (reason = error.response.message)
        new(error.response.status, reason, error.response, error)
    end
    function ApiException(resp::Downloads.Response; reason::String="")
        isempty(reason) && (reason = resp.message)
        new(resp.status, reason, resp, nothing)
    end
end

"""
    ApiResponse

Represents the HTTP API response from the server. This is returned as the second return value from all API calls.

Properties available:
- `status`: the HTTP status code
- `message`: the HTTP status message
- `headers`: the HTTP headers
- `raw`: the raw response ( as a Downloads.Response object)
"""
struct ApiResponse
    raw::Downloads.Response
end

function Base.getproperty(resp::ApiResponse, name::Symbol)
    raw = getfield(resp, :raw)
    if name === :status
        return raw.status
    elseif name === :message
        return raw.message
    elseif name === :headers
        return raw.headers
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
- `verbose`: Can be set either to a boolean or a function.
    - If set to true, then the client will log all HTTP requests and responses.
    - If set to a function, then that function will be called with the following parameters:
        - `type`: The type of message.
        - `message`: The message to be logged.

"""
struct Client
    root::String
    headers::Dict{String,String}
    get_return_type::Function   # user provided hook to get return type from response data
    clntoptions::Dict{Symbol,Any}
    downloader::Downloader
    timeout::Ref{Int}
    pre_request_hook::Function  # user provided hook to modify the request before it is sent
    escape_path_params::Union{Nothing,Bool}
    chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}
    long_polling_timeout::Int
    request_interrupt_supported::Bool

    function Client(root::String;
            headers::Dict{String,String}=Dict{String,String}(),
            get_return_type::Function=get_api_return_type,
            long_polling_timeout::Int=DEFAULT_LONGPOLL_TIMEOUT_SECS,
            timeout::Int=DEFAULT_TIMEOUT_SECS,
            pre_request_hook::Function=noop_pre_request_hook,
            escape_path_params::Union{Nothing,Bool}=nothing,
            chunk_reader_type::Union{Nothing,Type{<:AbstractChunkReader}}=nothing,
            verbose::Union{Bool,Function}=false,
        )
        clntoptions = Dict{Symbol,Any}(:throw=>false)
        if isa(verbose, Bool)
            clntoptions[:verbose] = verbose
        elseif isa(verbose, Function)
            clntoptions[:debug] = verbose
        end
        downloader = Downloads.Downloader()
        downloader.easy_hook = (easy, opts) -> begin
            Downloads.Curl.setopt(easy, LibCURL.CURLOPT_LOW_SPEED_TIME, long_polling_timeout)
            # disable ALPN to support servers that enable both HTTP/2 and HTTP/1.1 on same port
            Downloads.Curl.setopt(easy, LibCURL.CURLOPT_SSL_ENABLE_ALPN, 0)
        end
        interruptable = request_supports_interrupt()
        new(root, headers, get_return_type, clntoptions, downloader, Ref{Int}(timeout), pre_request_hook, escape_path_params, chunk_reader_type, long_polling_timeout, interruptable)
    end
end

"""
    set_user_agent(client::Client, ua::String)

Set the User-Agent header to be sent with all API calls.
"""
set_user_agent(client::Client, ua::String) = set_header(client, "User-Agent", ua)

"""
    set_cookie(client::Client, ck::String)

Set the Cookie header to be sent with all API calls.
"""
set_cookie(client::Client, ck::String) = set_header(client, "Cookie", ck)

"""
    set_header(client::Client, name::String, value::String)

Set the specified header to be sent with all API calls.
"""
set_header(client::Client, name::String, value::String) = (client.headers[name] = value)

"""
    set_timeout(client::Client, timeout::Int)

Set the timeout in seconds for all API calls.
"""
set_timeout(client::Client, timeout::Int) = (client.timeout[] = timeout)

function with_timeout(fn, client::Client, timeout::Integer)
    oldtimeout = client.timeout[]
    client.timeout[] = timeout
    try
        fn(client)
    finally
        client.timeout[] = oldtimeout
    end
end

function with_timeout(fn, api::APIClientImpl, timeout::Integer)
    client = api.client
    oldtimeout = client.timeout[]
    client.timeout[] = timeout
    try
        fn(api)
    finally
        client.timeout[] = oldtimeout
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

is_json_mime(mime::T) where {T <: AbstractString} = ("*/*" == mime) || occursin(r"(?i)application/json(;.*)?", mime) || occursin(r"(?i)application/(.*)\+json(;.*)?", mime)

function select_header_accept(accepts::Vector{String})
    isempty(accepts) && (return "application/json")
    for accept in accepts
        is_json_mime(accept) && (return accept)
    end
    return join(accepts, ", ")
end

function select_header_content_type(ctypes::Vector{String})
    isempty(ctypes) && (return "application/json")
    for ctype in ctypes
        is_json_mime(ctype) && (return (("*/*" == ctype) ? "application/json" : ctype))
    end
    return ctypes[1]
end

set_header_accept(ctx::Ctx, accepts::Vector{T}) where {T} = set_header_accept(ctx, convert(Vector{String}, accepts))
function set_header_accept(ctx::Ctx, accepts::Vector{String})
    accept = select_header_accept(accepts)
    !isempty(accept) && (ctx.header["Accept"] = accept)
    return nothing
end

set_header_content_type(ctx::Ctx, ctypes::Vector{T}) where {T} = set_header_content_type(ctx, convert(Vector{String}, ctypes))
function set_header_content_type(ctx::Ctx, ctypes::Vector{String})
    if !(ctx.method in ("GET", "HEAD"))
        ctx.header["Content-Type"] = select_header_content_type(ctypes)
    end
    return nothing
end

set_param(params::Dict{String,String}, name::String, value::Nothing; collection_format=",", style="form", location=:query, is_explode=default_param_explode(style)) = nothing
# Choose the default collection_format based on spec.
# Overriding it may not match the spec and there's no check.
# But we do not prevent it to allow for wiggle room, since there are many interpretations in the wild over the loosely defined spec around this.
# TODO: `default_param_explode` needs to be improved to handle location too (query, header, cookie...)
function default_param_explode(style::String)
    if style == "deepObject"
        true
    elseif style == "form"
        true
    else
        false
    end
end
function set_param(params::Dict{String,String}, name::String, value; collection_format=",", style="form", location::Symbol=:query, is_explode=default_param_explode(style))
    deep_explode = style == "deepObject" && is_explode
    if deep_explode
        merge!(params, deep_object_serialize(Dict(name=>value)))
        return nothing
    end
    if isa(value, Dict)
        # implements the default serialization (style=form, explode=true, location=queryparams)
        # as mentioned in https://swagger.io/docs/specification/serialization/
        for (k, v) in value
            params[k] = string(v)
        end
    elseif !isa(value, Vector) || isempty(collection_format)
        params[name] = string(value)
    else
        dlm = get(COLL_DLM, collection_format, ",")
        isempty(dlm) && throw(OpenAPIException("Unsupported collection format $collection_format"))
        params[name] = join(string.(value), dlm)
    end
end

function prep_args(ctx::Ctx)
    kwargs = copy(ctx.client.clntoptions)
    kwargs[:downloader] = ctx.client.downloader     # use the default downloader for most cases

    isempty(ctx.file) && (ctx.body === nothing) && isempty(ctx.form) && !("Content-Length" in keys(ctx.header)) && (ctx.header["Content-Length"] = "0")
    headers = ctx.header
    body = nothing

    header_pairs = [convert(HTTP.Header, p) for p in headers]
    content_type_set = HTTP.header(header_pairs, "Content-Type", nothing)
    if !isnothing(content_type_set)
        content_type_set = lowercase(content_type_set)
    end

    if !isempty(ctx.form)
        if !isnothing(content_type_set) && content_type_set !== "multipart/form-data" && content_type_set !== "application/x-www-form-urlencoded"
            throw(OpenAPIException("Content type already set to $content_type_set. To send form data, it must be multipart/form-data or application/x-www-form-urlencoded."))
        end
        if isnothing(content_type_set)
            if !isempty(ctx.file)
                headers["Content-Type"] = content_type_set = "multipart/form-data"
            else
                headers["Content-Type"] = content_type_set = "application/x-www-form-urlencoded"
            end
        end
        if content_type_set == "application/x-www-form-urlencoded"
            body = URIs.escapeuri(ctx.form)
        else
            # we shall process it along with file uploads where we send multipart/form-data
        end
    end

    if !isempty(ctx.file) || (content_type_set == "multipart/form-data")
        if !isnothing(content_type_set) && content_type_set !== "multipart/form-data"
            throw(OpenAPIException("Content type already set to $content_type_set. To send file, it must be multipart/form-data."))
        end

        if isnothing(content_type_set)
            headers["Content-Type"] = content_type_set = "multipart/form-data"
        end

        # use a separate downloader for file uploads
        # until we have something like https://github.com/JuliaLang/Downloads.jl/pull/148
        downloader = Downloads.Downloader()
        downloader.easy_hook = (easy, opts) -> begin
            Downloads.Curl.setopt(easy, LibCURL.CURLOPT_LOW_SPEED_TIME, ctx.client.long_polling_timeout)
            mime = ctx.curl_mime_upload[]
            if mime === nothing
                mime = LibCURL.curl_mime_init(easy.handle)
                ctx.curl_mime_upload[] = mime
            end
            for (_k,_v) in ctx.file
                part = LibCURL.curl_mime_addpart(mime)
                LibCURL.curl_mime_name(part, _k)
                LibCURL.curl_mime_filedata(part, _v)
                # TODO: make provision to call curl_mime_type in future?
            end
            for (_k,_v) in ctx.form
                # add multipart sections for form data as well
                part = LibCURL.curl_mime_addpart(mime)
                LibCURL.curl_mime_name(part, _k)
                LibCURL.curl_mime_data(part, _v, length(_v))
            end
            Downloads.Curl.setopt(easy, LibCURL.CURLOPT_MIMEPOST, mime)
        end
        kwargs[:downloader] = downloader
    end

    if ctx.body !== nothing
        (isempty(ctx.form) && isempty(ctx.file)) || throw(OpenAPIException("Can not send both form-encoded data and a request body"))
        if is_json_mime(something(content_type_set, "application/json"))
            body = to_json(ctx.body)
        elseif ("application/x-www-form-urlencoded" == content_type_set) && isa(ctx.body, Dict)
            body = URIs.escapeuri(ctx.body)
        elseif isa(ctx.body, APIModel) && isnothing(content_type_set)
            headers["Content-Type"] = content_type_set = "application/json"
            body = to_json(ctx.body)
        else
            body = ctx.body
        end
    end

    kwargs[:timeout] = ctx.timeout
    kwargs[:method] = uppercase(ctx.method)
    kwargs[:headers] = headers

    return body, kwargs
end

function header(resp::Downloads.Response, name::AbstractString, defaultval::AbstractString)
    for (n,v) in resp.headers
        (lowercase(n) == lowercase(name)) && (return v)
    end
    return defaultval
end

response(::Type{Nothing}, resp::Downloads.Response, body) = nothing::Nothing
response(::Type{T}, resp::Downloads.Response, body) where {T <: Real} = response(T, body)::T
response(::Type{T}, resp::Downloads.Response, body) where {T <: String} = response(T, body)::T
function response(::Type{T}, resp::Downloads.Response, body) where {T}
    ctype = header(resp, "Content-Type", "application/json")
    response(T, is_json_mime(ctype), body)::T
end
response(::Type{T}, ::Nothing, body) where {T} = response(T, true, body)
function response(::Type{T}, is_json::Bool, body) where {T}
    (length(body) == 0) && return T()
    response(T, is_json ? JSON.parse(String(body)) : body)::T
end
response(::Type{String}, data::Vector{UInt8}) = String(data)
response(::Type{T}, data::Vector{UInt8}) where {T<:Real} = parse(T, String(data))
response(::Type{T}, data::T) where {T} = data

response(::Type{ZonedDateTime}, data) = str2zoneddatetime(data)
response(::Type{DateTime}, data) = str2datetime(data)
response(::Type{Date}, data) = str2date(data)

response(::Type{T}, data) where {T} = convert(T, data)
response(::Type{T}, data::Dict{String,Any}) where {T} = from_json(T, data)::T
response(::Type{T}, data::Dict{String,Any}) where {T<:Dict} = convert(T, data)
response(::Type{Vector{T}}, data::Vector{V}) where {T,V} = T[response(T, v) for v in data]

struct LineChunkReader <: AbstractChunkReader
    buffered_input::Base.BufferStream
end

function Base.iterate(iter::LineChunkReader, _state=nothing)
    if eof(iter.buffered_input)
        return nothing
    else
        out = IOBuffer()
        while !eof(iter.buffered_input)
            byte = read(iter.buffered_input, UInt8)
            (byte == codepoint('\n')) && break
            write(out, byte)
        end
        return (take!(out), iter)
    end
end

struct JSONChunkReader <: AbstractChunkReader
    buffered_input::Base.BufferStream
end

function Base.iterate(iter::JSONChunkReader, _state=nothing)
    if eof(iter.buffered_input)
        return nothing
    else
        # read all whitespaces
        while !eof(iter.buffered_input)
            byte = peek(iter.buffered_input, UInt8)
            if isspace(Char(byte))
                read(iter.buffered_input, UInt8)
            else
                break
            end
        end
        eof(iter.buffered_input) && return nothing
        valid_json = JSON.parse(iter.buffered_input)
        bytes = convert(Vector{UInt8}, codeunits(JSON.json(valid_json)))
        return (bytes, iter)
    end
end

# Ref: https://www.rfc-editor.org/rfc/rfc7464.html
const RFC7464_RECORD_SEPARATOR = UInt8(0x1E)
struct RFC7464ChunkReader <: AbstractChunkReader
    buffered_input::Base.BufferStream
end

function Base.iterate(iter::RFC7464ChunkReader, _state=nothing)
    if eof(iter.buffered_input)
        return nothing
    else
        out = IOBuffer()
        while !eof(iter.buffered_input)
            byte = read(iter.buffered_input, UInt8)
            if byte == RFC7464_RECORD_SEPARATOR
                bytes = take!(out)
                if isnothing(_state) || !isempty(bytes)
                    return (bytes, iter)
                end
            else
                write(out, byte)
            end
        end
        bytes = take!(out)
        return (bytes, iter)
    end
end

noop_pre_request_hook(ctx::Ctx) = ctx
noop_pre_request_hook(resource_path::AbstractString, body::Any, headers::Dict{String,String}) = (resource_path, body, headers)

function do_request(ctx::Ctx, stream::Bool=false; stream_to::Union{Channel,Nothing}=nothing)
    # call the user hook to allow them to modify the request context
    ctx = ctx.pre_request_hook(ctx)

    # prepare the url
    resource_path = replace(ctx.resource, "{format}"=>"json")
    for (k,v) in ctx.path
        esc_v = ctx.escape_path_params ? escapeuri(v) : v
        resource_path = replace(resource_path, "{$k}"=>esc_v)
    end
    # append query params if needed
    if !isempty(ctx.query)
        resource_path = string(URIs.URI(URIs.URI(resource_path); query=escapeuri(ctx.query)))
    end

    body, kwargs = prep_args(ctx)

    # call the user hook again, to allow them to modify the processed request
    resource_path, body, headers = ctx.pre_request_hook(resource_path, body, kwargs[:headers])
    kwargs[:headers] = headers

    if body !== nothing
        input = PipeBuffer()
        write(input, body)
    else
        input = nothing
    end

    if stream
        @assert stream_to !== nothing
    end

    resp = nothing
    output = Base.BufferStream()

    try
        if stream
            interrupt = nothing
            if ctx.client.request_interrupt_supported
                kwargs[:interrupt] = interrupt = Base.Event()
            end
            @sync begin
                download_task = @async begin
                    try
                        resp = Downloads.request(resource_path;
                            input=input,
                            output=output,
                            kwargs...
                        )
                    catch ex
                        # If request method does not support interrupt natively, InterrptException is used to
                        # signal the download task to stop. Otherwise, InterrptException is not handled and is rethrown.
                        # Any exception other than InterruptException is rethrown always.
                        if ctx.client.request_interrupt_supported || !isa(ex, InterruptException)
                            @error("exception invoking request", exception=(ex,catch_backtrace()))
                            rethrow()
                        end
                    finally
                        close(output)
                    end
                end
                @async begin
                    try
                        if isnothing(ctx.chunk_reader_type)
                            default_return_type = ctx.client.get_return_type(ctx.return_types, nothing, "")
                            readerT = default_return_type <: APIModel ? JSONChunkReader : LineChunkReader
                        else
                            readerT = ctx.chunk_reader_type
                        end
                        for chunk in readerT(output)
                            return_type = ctx.client.get_return_type(ctx.return_types, nothing, String(copy(chunk)))
                            data = response(return_type, resp, chunk)
                            put!(stream_to, data)
                        end
                    catch ex
                        if !isa(ex, InvalidStateException) && isopen(stream_to)
                            @error("exception reading chunk", exception=(ex,catch_backtrace()))
                            rethrow()
                        end
                    finally
                        close(stream_to)
                    end
                end
                @async begin
                    interrupted = false
                    while isopen(stream_to)
                        try
                            wait(stream_to)
                            yield()
                        catch ex
                            isa(ex, InvalidStateException) || rethrow(ex)
                            interrupted = true
                            if !istaskdone(download_task)
                                # If the download task is still running, interrupt it.
                                # If it supports interrupt natively, then use event to signal it.
                                # Otherwise, throw an InterruptException to stop the download task.
                                if ctx.client.request_interrupt_supported
                                    notify(interrupt)
                                else
                                    schedule(download_task, InterruptException(), error=true)
                                end
                            end
                        end
                    end
                    if !interrupted && !istaskdone(download_task)
                        if ctx.client.request_interrupt_supported
                            notify(interrupt)
                        else
                            schedule(download_task, InterruptException(), error=true)
                        end
                    end
                end
            end
        else
            resp = Downloads.request(resource_path;
                        input=input,
                        output=output,
                        kwargs...
                    )
            close(output)
        end
    finally
        if ctx.curl_mime_upload[] !== nothing
            LibCURL.curl_mime_free(ctx.curl_mime_upload[])
            ctx.curl_mime_upload[] = nothing
        end
    end

    return resp, output
end

function exec(ctx::Ctx, stream_to::Union{Channel,Nothing}=nothing)
    stream = stream_to !== nothing
    resp, output = do_request(ctx, stream; stream_to=stream_to)

    if resp === nothing
        # request was interrupted
        throw(InvocationException("request was interrupted"))
    end

    if isa(resp, Downloads.RequestError)
        throw(ApiException(resp))
    end

    if stream
        return stream_to, ApiResponse(resp)
    else
        data = read(output)
        return_type = ctx.client.get_return_type(ctx.return_types, resp.status, String(copy(data)))
        if isnothing(return_type)
            return nothing, ApiResponse(resp)
        end
        return response(return_type, resp, data), ApiResponse(resp)
    end
end

function setproperty!(o::T, name::Symbol, val) where {T<:APIModel}
    validate_property(T, name, val)
    fieldtype = property_type(T, name)

    if isa(val, fieldtype)
        return setfield!(o, name, val)
    elseif fieldtype === ZonedDateTime
        return setfield!(o, name, str2zoneddatetime(val))
    elseif fieldtype === DateTime
        return setfield!(o, name, str2datetime(val))
    elseif fieldtype === Date
        return setfield!(o, name, str2date(val))
    else
        ftval = try
            convert(fieldtype, val)
        catch
            fieldtype(val)
        end
        return setfield!(o, name, ftval)
    end
end

"""
    getpropertyat(o::T, path...) where {T<:APIModel}

Returns the property at the specified path.
The path can be a single property name or a chain of property names separated by dots, representing a nested property.
"""
function getpropertyat(o::T, path...) where {T<:APIModel}
    val = getproperty(o, Symbol(path[1]))
    rempath = path[2:end]
    (length(rempath) == 0) && (return val)

    if isa(val, Vector)
        if isa(rempath[1], Integer)
            val = val[rempath[1]]
            rempath = rempath[2:end]
        else
            return [getpropertyat(item, rempath...) for item in val]
        end
    end

    (length(rempath) == 0) && (return val)
    getpropertyat(val, rempath...)
end

"""
    haspropertyat(o::T, path...) where {T<:APIModel}

Returns true if the supplied object has the property at the specified path.
"""
function haspropertyat(o::T, path...) where {T<:APIModel}
    p1 = Symbol(path[1])
    ret = hasproperty(o, p1)
    rempath = path[2:end]
    (length(rempath) == 0) && (return ret)
    ret || (return false)

    val = getproperty(o, p1)
    if isa(val, Vector)
        if isa(rempath[1], Integer)
            ret = length(val) >= rempath[1]
            if ret
                val = val[rempath[1]]
                rempath = rempath[2:end]
            end
        else
            return [haspropertyat(item, rempath...) for item in val]
        end
    end

    (length(rempath) == 0) && (return ret)
    haspropertyat(val, rempath...)
end

Base.hasproperty(o::T, name::Symbol) where {T<:APIModel} = ((name in propertynames(o)) && (getproperty(o, name) !== nothing))

convert(::Type{T}, json::Dict{String,Any}) where {T<:APIModel} = from_json(T, json)
convert(::Type{T}, v::Nothing) where {T<:APIModel} = T()
convert(::Type{T}, v::T) where {T<:OneOfAPIModel} = v
convert(::Type{T}, json::Dict{String,Any}) where {T<:OneOfAPIModel} = from_json(T, json)
convert(::Type{T}, v) where {T<:OneOfAPIModel} = T(v)
convert(::Type{T}, v::String) where {T<:OneOfAPIModel} = T(v)
convert(::Type{T}, v::T) where {T<:AnyOfAPIModel} = v
convert(::Type{T}, json::Dict{String,Any}) where {T<:AnyOfAPIModel} = from_json(T, json)
convert(::Type{T}, v) where {T<:AnyOfAPIModel} = T(v)
convert(::Type{T}, v::String) where {T<:AnyOfAPIModel} = T(v)

show(io::IO, model::T) where {T<:UnionAPIModel} = print(io, JSON.json(model.value, 2))
show(io::IO, model::T) where {T<:APIModel} = print(io, JSON.json(model, 2))
summary(io::IO, model::T) where {T<:APIModel} = print(io, T)

"""
    is_longpoll_timeout(ex::Exception)

Examine the supplied exception and return true if the reason is timeout
of a long polling request. If the exception is a nested exception of type
CompositeException or TaskFailedException, then navigates through the nested
exception values to examine the leaves.
"""
is_longpoll_timeout(ex) = false
is_longpoll_timeout(ex::TaskFailedException) = is_longpoll_timeout(ex.task.exception)
is_longpoll_timeout(ex::CompositeException) = any(is_longpoll_timeout, ex.exceptions)
function is_longpoll_timeout(ex::ApiException)
    ex.status == 200 && match(r"Operation timed out after \d+ milliseconds with \d+ bytes received", ex.reason) !== nothing
end

"""
    is_request_interrupted(ex::Exception)

Examine the supplied exception and return true if the reason is that the
request was interrupted. If the exception is a nested exception of type
CompositeException or TaskFailedException, then navigates through the nested
exception values to examine the leaves.
"""
is_request_interrupted(ex) = false
is_request_interrupted(ex::TaskFailedException) = is_request_interrupted(ex.task.exception)
is_request_interrupted(ex::CompositeException) = any(is_request_interrupted, ex.exceptions)
is_request_interrupted(ex::InvocationException) = ex.reason == "request was interrupted"


"""
    storefile(api_call::Function;
        folder::AbstractString = pwd(),
        rename_file::String="",
        )::Tuple{Any,ApiResponse,String}

    Helper method that stores the result of an API call that returns file
    contents (as binary or text string) into a file.

    Convenient to use it in a do block. Returns the path where file is stored additionally.

    E.g.:
    ```
    _result, _http_response, file = OpenAPI.Clients.storefile() do
        # Invoke the OpenaPI method that returns file contents.
        # This is the method that returns a tuple of (result, http_response).
        # The result is the file contents as binary or text string.
        fetch_file(api, "reports", "category1")
    end
    ```

    Parameters:

    - `api_call`: The OpenAPI function call that returns file contents (as binary or text string). See example in method description.
    - `folder`: Location to store file, defaults to `pwd()`.
    - `filename`: Use this filename, overrides any filename that may be there in the `Content-Disposition` header.

    Returns: (result, http_response, file_path)
"""
function storefile(api_call::Function;
    folder::AbstractString = pwd(),
    filename::Union{String,Nothing} = nothing,
    )::Tuple{Any,ApiResponse,String}

    result, http_response = api_call()

    if isnothing(filename)
        filename = extract_filename(http_response)
    end

    mkpath(folder)
    filepath = joinpath(folder, filename)

    open(filepath, "w") do io
        write(io, result)
    end

    return result, http_response, filepath
end

const content_disposition_re = r"filename\*?=['\"]?(?:UTF-\d['\"]*)?([^;\r\n\"']*)['\"]?;?"

"""
    extract_filename(resp::Downloads.Response)::String

Extracts the filename from the `Content-Disposition` header of the HTTP response.
If not found, then creates a filename from the `Content-Type` header.
"""
extract_filename(resp::ApiResponse) = extract_filename(resp.raw)
function extract_filename(resp::Downloads.Response)::String
    # attempt to extract filename from content-disposition header
    content_disposition_str = header(resp, "content-disposition", "")
    m = match(content_disposition_re, content_disposition_str)
    if !isnothing(m) && !isempty(m.captures) && !isnothing(m.captures[1])
        return m.captures[1]
    end

    # attempt to create a filename from content-type header
    content_type_str = header(resp, "content-type", "")
    return string("response", extension_from_mime(MIME(content_type_str)))
end

function deep_object_serialize(dict::Dict, parent_key::String = "")
    parts = Pair[]
    for (key, value) in dict
        new_key = parent_key == "" ? key : "$parent_key[$key]"
        if isa(value, Dict)
            append!(parts, collect(deep_object_serialize(value, new_key)))
        elseif isa(value, Vector)
            for (i, v) in enumerate(value)
                push!(parts, "$new_key[$(i-1)]"=>"$v")
            end
        else
            push!(parts, "$new_key"=>"$value")
        end
    end
    return Dict(parts)
end

function request_supports_interrupt()
    for m in methods(request)
        if :interrupt in Base.kwarg_decl(m)
            return true
        end
    end
    return false
end

end # module Clients
