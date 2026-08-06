# Lets OpenAPI.read fetch documents over HTTP (e.g. a running app's
# /openapi.json), and adds the `framework = :HTTP` server-stub emitter that
# mounts generated operations on an `HTTP.Router`. Loads automatically when
# both OpenAPI and HTTP are loaded.
module OpenAPIHTTPExt

using OpenAPI, HTTP

function OpenAPI.fetchresource(id::OpenAPI.Resources.ResourceId, max_bytes::Integer)
    body = Vector{UInt8}(undef, max_bytes)
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
        if occursin("response stream", message) ||
           occursin("DecompressionLimitError", message)
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
    bytes = copy(body)
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
        bytes = Vector{UInt8}(codeunits(String(request.body)))
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

end # module
