# Lets OpenAPI.read fetch documents over HTTP (e.g. a running app's
# /openapi.json), and adds the `framework = :HTTP` server-stub emitter that
# mounts generated operations on an `HTTP.Router`. Loads automatically when
# both OpenAPI and HTTP are loaded.
module OpenAPIHTTPExt

using OpenAPI, HTTP
using PrecompileTools: @compile_workload

struct _ResponseTooLarge <: Exception end

mutable struct _BoundedResponseBuffer <: IO
    buffer::IOBuffer
    max_bytes::Int
end

Base.isopen(buffer::_BoundedResponseBuffer) = isopen(buffer.buffer)
Base.position(buffer::_BoundedResponseBuffer) = position(buffer.buffer)
function Base.unsafe_write(
    buffer::_BoundedResponseBuffer,
    pointer::Ptr{UInt8},
    bytes::UInt,
)
    bytes <= buffer.max_bytes - position(buffer) || throw(_ResponseTooLarge())
    return Base.unsafe_write(buffer.buffer, pointer, bytes)
end

function OpenAPI.fetchresource(id::OpenAPI.Resources.ResourceId, max_bytes::Integer)
    body = _BoundedResponseBuffer(IOBuffer(), Int(max_bytes))
    response = try
        HTTP.get(
            string(id);
            status_exception = false,
            redirect = false,
            retry = false,
            response_stream = body,
            max_decompressed_size = max_bytes,
            request_timeout = 60,
            read_idle_timeout = 15,
        )
    catch error
        message = sprint(showerror, error)
        if error isa _ResponseTooLarge || error isa HTTP.DecompressionLimitError
            throw(
                OpenAPI.Resources.RetrievalError(
                    id,
                    "HTTP response exceeds the $max_bytes-byte limit",
                ),
            )
        end
        throw(
            OpenAPI.Resources.RetrievalError(
                id,
                "HTTP request failed: $message",
            ),
        )
    end
    200 <= response.status < 300 || throw(
        OpenAPI.Resources.RetrievalError(
            id,
            "HTTP request returned status $(response.status)",
        ),
    )
    bytes = take!(body.buffer)
    media_type = HTTP.header(response, "Content-Type", "")
    return OpenAPI.Resources.RetrievedResource(
        id,
        bytes;
        media_type = isempty(media_type) ? nothing : media_type,
    )
end

OpenAPI.fetchurl(url::AbstractString) = String(
    getfield(
        OpenAPI.fetchresource(OpenAPI.Resources.ResourceId(url), 16 * 1024 * 1024),
        :bytes,
    ),
)

# ── server-stub emission for HTTP.Router ─────────────────────────────────────

const GENERATED_HTTP_SERVER_IMPORTS = "using HTTP, JSON, OpenAPI, Base64, Dates, UUIDs"

const GENERATED_HTTP_SERVER_GLUE = raw"""
function _missing_implementations(impl)
    missing_ops = String[]
    for entry in _SERVER_OPS
        isdefined(impl, entry.invoke) || push!(missing_ops, entry.signature)
    end
    return missing_ops
end

function _http_query(request::HTTP.Request)
    target = String(request.target)
    index = findfirst('?', target)
    return index === nothing ? "" : String(SubString(target, index + 1))
end

function _http_multipart_parts(content_type, bytes)
    startswith(_base_media_type(content_type), "multipart/") || return nothing
    parts = HTTP.parse_multipart_form(String(content_type), bytes)
    parts === nothing && return nothing
    return [
        (
            name = String(part.name),
            filename = part.filename,
            content_type = String(part.contenttype),
            data = read(part.data),
        ) for part in parts
    ]
end

function _http_handler(impl, entry)
    return function (request::HTTP.Request)
        content_values = _header_values(request.headers, "Content-Type")
        content_type = isempty(content_values) ? "" : first(content_values)
        bytes = request.body isa AbstractVector{UInt8} ? copy(request.body) :
                Vector{UInt8}(codeunits(String(request.body)))
        local args, kwargs
        try
            parts = _http_multipart_parts(content_type, bytes)
            args, kwargs = _operation_arguments(
                entry,
                something(HTTP.getparams(request), Dict{String,String}()),
                _http_query(request),
                request.headers,
                bytes,
                parts,
            )
        catch error
            status, headers, payload = _request_error_response(error)
            return HTTP.Response(status, headers, payload)
        end
        result = getfield(impl, entry.invoke)(request, args...; kwargs...)
        result isa HTTP.Response && return result
        status, headers, payload = try
            _server_response(entry.operation, result)
        catch error
            _response_error_payload(error)
        end
        return HTTP.Response(status, headers, payload)
    end
end

# register!(router::HTTP.Router, impl; path_prefix = "", middleware = nothing)
#
# Mount every documented operation on `router`, dispatching to the handler
# functions `impl` defines (one per operation; the expected signatures are
# listed at the top of this file). Handlers may return a documented typed
# value (encoded and validated automatically), `nothing` (a 204 response), or
# a full `HTTP.Response` for anything custom. `middleware` wraps each
# operation handler: `middleware(handler) -> handler`. `register` is an alias
# kept for familiarity with OpenAPI.jl 0.2.x generated servers.
function register!(
    router::HTTP.Router,
    impl;
    path_prefix::AbstractString = "",
    middleware = nothing,
)
    missing_ops = _missing_implementations(impl)
    isempty(missing_ops) || throw(ArgumentError(string(
        "implementation is missing handler functions:\n    ",
        join(missing_ops, "\n    "),
    )))
    for entry in _SERVER_OPS
        handler = _http_handler(impl, entry)
        middleware === nothing || (handler = middleware(handler))
        HTTP.register!(router, entry.method, string(path_prefix, entry.path), handler)
    end
    return router
end
const register = register!
"""

OpenAPI.server_source(::Val{:HTTP}, plan::OpenAPI.ServerPlan) =
    OpenAPI.server_module_source(
        plan;
        imports = GENERATED_HTTP_SERVER_IMPORTS,
        glue = GENERATED_HTTP_SERVER_GLUE,
    )

# ---- Generated-client HTTP transport (methods on OpenAPI.Runtime stubs) ----
import OpenAPI.Runtime:
    ABSENT,
    Absent,
    ApiError,
    ApiResponse,
    Client,
    _append_parameter!,
    _base_media_type,
    _decode_response_headers,
    _decode_stream_item,
    _drain_stream_buffer!,
    _encode,
    _encode_body,
    _escape,
    _finish_buffered_response,
    _header_values,
    _safe_header,
    _security!,
    _select_media,
    _select_response,
    _selected_media_entry,
    _server_for,
    _set_header!,
    _stream_codec_media,
    _stream_plan,
    _validate_schema
import OpenAPI.Runtime: _request, _stream_request, _pump_stream!, _abort_stream_on_close!

function _request(
    client::Client,
    operation,
    values::Dict{Symbol,Any};
    body = ABSENT,
    content_type = nothing,
    accept = nothing,
    with_http_info::Bool = false,
    request_headers = Pair{String,String}[],
    request_options::NamedTuple = NamedTuple(),
    multipart_headers = NamedTuple(),
    stream_to::Union{Nothing,Channel} = nothing,
)
    path = operation.path
    query = Tuple{String,String,Bool,Bool}[]
    headers = Pair{String,String}[_safe_header(key, value) for (key, value) in client.headers]
    for (key, value) in request_headers
        _set_header!(headers, key, value)
    end
    cookies = Tuple{String,String,Bool,Bool}[]
    for descriptor in operation.parameters
        value = get(values, descriptor.arg, ABSENT)
        if value isa Absent
            descriptor.required &&
                throw(ArgumentError("required parameter $(descriptor.name) is missing"))
            continue
        end
        client.validate_requests && _validate_schema(client.spec, 
            descriptor.schema,
            _encode(value),
            "encoding parameter $(descriptor.name)";
            direction = :input,
        )
        path = _append_parameter!(
            client,
            path,
            query,
            headers,
            cookies,
            descriptor,
            value,
        )
    end
    occursin('{', path) &&
        throw(ArgumentError("not all path template parameters were supplied for $(operation.id)"))
    default_options = stream_to isa Channel ? (; protocol = :h1) : NamedTuple()
    base_options = merge(default_options, client.request_options, request_options)
    options = _security!(
        client,
        operation.security,
        query,
        headers,
        cookies,
        base_options,
    )
    if !isempty(cookies)
        cookie_text = join(
            (
                fragment ? key :
                (raw ? key : _escape(key)) * "=" *
                (raw ? value : _escape(value)) for
                (key, value, raw, fragment) in cookies
            ),
            "; ",
        )
        existing = join(_header_values(headers, "Cookie"), "; ")
        _set_header!(
            headers,
            "Cookie",
            isempty(existing) ? cookie_text : existing * "; " * cookie_text,
        )
        options = merge(options, (; cookies = false))
    end
    query_text = isempty(query) ? "" : "?" * join(
        (
            _escape(key) * "=" *
            (preencoded ? value : _escape(value; allow_reserved)) for
            (key, value, allow_reserved, preencoded) in query
        ),
        '&',
    )
    url = _server_for(client, operation) *
          (startswith(path, '/') ? path : "/" * path) * query_text

    payload = UInt8[]
    if operation.request !== nothing && !(body isa Absent)
        media = operation.request.media
        entry = content_type === nothing ? first(media) :
                _select_media(media, String(content_type))
        entry === nothing && throw(
            ArgumentError("unsupported request Content-Type $(repr(content_type)) for $(operation.id)"),
        )
        client.validate_requests && _validate_schema(client.spec, 
            entry[3],
            _encode(body),
            "encoding the $(operation.id) request body";
            direction = :input,
        )
        payload, actual_content_type =
            _encode_body(
                client,
                body,
                entry[1],
                entry[4];
                multipart_headers,
            )
        _set_header!(headers, "Content-Type", actual_content_type)
    elseif operation.request !== nothing && operation.request.required
        throw(ArgumentError("required request body is missing for $(operation.id)"))
    end
    documented_accept = String[
        entry[1] for response in operation.responses for entry in response.media
        if startswith(uppercase(response.selector), "2") ||
           uppercase(response.selector) == "DEFAULT"
    ]
    existing_accept = _header_values(headers, "Accept")
    selected_accept = if accept !== nothing
        String(accept)
    elseif !isempty(existing_accept)
        nothing
    else
        join(unique(documented_accept), ", ")
    end
    selected_accept === nothing || isempty(selected_accept) ||
        _set_header!(headers, "Accept", selected_accept)

    stream_to === nothing || return _stream_request(
        client,
        operation,
        url,
        headers,
        payload,
        options,
        accept,
        stream_to,
        with_http_info,
    )
    options = merge(options, (body = payload, status_exception = false))
    response = HTTP.request(
        operation.method,
        url,
        headers;
        options...,
    )
    response_headers = Pair{String,String}[
        String(key) => String(value) for (key, value) in response.headers
    ]
    return _finish_buffered_response(
        client,
        operation,
        Int(response.status),
        response_headers,
        HTTP.header(response, "Content-Type", ""),
        Vector{UInt8}(response.body),
        with_http_info,
    )
end

function _pump_stream!(
    client::Client,
    stream,
    channel::Channel,
    kind::Symbol,
    item_type,
    schema,
    media_type,
    finished,
)
    buffer = UInt8[]
    try
        while !eof(stream)
            chunk = readavailable(stream)
            isempty(chunk) && continue
            if kind === :bytes
                put!(
                    channel,
                    _decode_stream_item(
                        client,
                        chunk,
                        kind,
                        item_type,
                        schema,
                        media_type,
                    ),
                )
            else
                append!(buffer, chunk)
                _drain_stream_buffer!(
                    client,
                    channel,
                    buffer,
                    kind,
                    item_type,
                    schema,
                    media_type,
                    false,
                )
            end
        end
        kind === :bytes || _drain_stream_buffer!(
            client,
            channel,
            buffer,
            kind,
            item_type,
            schema,
            media_type,
            true,
        )
        finished[] = true
        close(channel)
    catch error
        # A channel the consumer closed is the abort signal; anything else is
        # delivered to the consumer through the channel.
        if isopen(channel)
            finished[] = true
            close(channel, error)
        end
    finally
        try
            HTTP.closeread(stream)
        catch
        end
        finished[] = true
    end
    return nothing
end

function _abort_stream_on_close!(stream, channel::Channel, producer::Task, finished)
    while isopen(channel) && !finished[]
        sleep(0.25)
    end
    finished[] && return nothing
    try
        HTTP.closeread(stream)
    catch
    end
    for _ in 1:4
        istaskdone(producer) && return nothing
        sleep(0.25)
    end
    try
        close(stream)
    catch
    end
    return nothing
end

function _stream_request(
    client::Client,
    operation,
    url,
    headers,
    payload::Vector{UInt8},
    options,
    accept,
    stream_to::Channel,
    with_http_info::Bool,
)
    stream = HTTP.open(operation.method, url, headers; options...)
    local response
    try
        isempty(payload) || write(stream, payload)
        HTTP.closewrite(stream)
        response = HTTP.startread(stream)
    catch
        try
            HTTP.closeread(stream)
        catch
        end
        rethrow()
    end
    response_headers = Pair{String,String}[
        String(key) => String(value) for (key, value) in response.headers
    ]
    received = HTTP.header(response, "Content-Type", "")
    status = Int(response.status)
    if !(200 <= status < 300)
        bytes = try
            read(stream)
        finally
            try
                HTTP.closeread(stream)
            catch
            end
        end
        # Throws ApiError with the fully decoded error body.
        return _finish_buffered_response(
            client,
            operation,
            status,
            response_headers,
            received,
            bytes,
            with_http_info,
        )
    end
    local descriptor, decoded_headers, kind, item_type, schema, actual_media
    try
        descriptor = _select_response(operation.responses, status)
        decoded_headers = _decode_response_headers(client, descriptor, response_headers)
        if descriptor === nothing || isempty(descriptor.media)
            actual_media = isempty(received) ? "application/octet-stream" : String(received)
            kind, item_type, schema = :bytes, Vector{UInt8}, nothing
        else
            selected, actual_media =
                _selected_media_entry(operation.id, status, descriptor, received)
            kind, item_type, schema =
                _stream_plan(_base_media_type(actual_media), selected[2], selected[3])
        end
    catch
        try
            HTTP.closeread(stream)
        catch
        end
        rethrow()
    end
    finished = Ref(false)
    producer = errormonitor(@async _pump_stream!(
        client,
        stream,
        stream_to,
        kind,
        item_type,
        schema,
        _stream_codec_media(client, actual_media, accept),
        finished,
    ))
    errormonitor(@async _abort_stream_on_close!(stream, stream_to, producer, finished))
    return with_http_info ?
           ApiResponse(status, response_headers, decoded_headers, stream_to) :
           stream_to
end

# HTTP adds methods to OpenAPI's transport seams after the core package image
# is loaded. Re-run the small client workload in this final method world so the
# extension does not leave loading and generation work for the first request.
precompile(
    OpenAPI.fetchresource,
    (OpenAPI.Resources.ResourceId, Int),
)

@compile_workload begin
    precompile_source = OpenAPI.read(
        OpenAPI._PRECOMPILE_CLIENT_DOCUMENT;
        base_uri = "https://precompile.openapi.invalid/openapi.json",
    )
    null_path = Sys.iswindows() ? "NUL" : "/dev/null"
    OpenAPI.client(precompile_source; name = "PrecompileHTTPClient", path = null_path)
end

end # module
