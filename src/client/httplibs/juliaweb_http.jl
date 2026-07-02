# =============================================================================
# HTTP.jl Backend Implementation
# =============================================================================
# This file implements the HTTP client backend using the HTTP.jl (JuliaWeb) library.
#
# Dependencies:
#   - HTTP: Primary HTTP client library from JuliaWeb
#   - URIs: For URI escaping and query parameter handling
#
# Public Interface (via Val dispatch):
#   - prep_args(::Val{:http}, ctx::Ctx)
#   - do_request(::Val{:http}, ctx, ...)
#
# Type-Specific Methods:
#   - get_response_property(::HTTP.Response, ...)
#   - get_response_header(::HTTP.Response, ...)
#   - get_message(::HTTPRequestError)
#   - get_response(::HTTPRequestError)
#   - get_status(::HTTPRequestError)
#
# Custom Types:
#   - HTTPRequestError <: AbstractHTTPLibError
# =============================================================================

# HTTP.jl 2.0 reworked much of the public API; we support both 1.x and 2.x and
# branch on the major version at load time. `pkgversion` exists from Julia 1.9;
# on older Julia only HTTP 1.x can be installed (HTTP 2.0 needs Julia >= 1.10).
const _HTTP_V2 = isdefined(Base, :pkgversion) && something(pkgversion(HTTP), v"1") >= v"2"

# Status reason text: `HTTP.Messages.statustext` on 1.x, `Response.reason` on 2.x.
function _http_statustext(raw::HTTP.Response)
    if isdefined(HTTP, :Messages)
        return HTTP.Messages.statustext(raw.status)
    elseif hasproperty(raw, :reason) && !isempty(raw.reason)
        return raw.reason
    else
        return string(raw.status)
    end
end

# Case-insensitive header lookup over the request header collection (a Dict).
# Avoids `HTTP.Header`/`HTTP.header(::Vector, ...)`, both removed in 2.0.
function _header_value_ci(headers, key::AbstractString)
    lk = lowercase(key)
    for (k, v) in headers
        lowercase(String(k)) == lk && return String(v)
    end
    return nothing
end

# Form content type: `HTTP.content_type` returns a `Pair` on 1.x, a `String` on 2.x.
_http_form_content_type(body) = (ct = HTTP.content_type(body); ct isa Pair ? ct[2] : ct)

# Timeout budget in ms: `TimeoutError.readtimeout` (s) on 1.x, `.timeout_ns` on 2.x.
# Keep this an integer — the reason string is later matched against `\d+ milliseconds`.
_http_timeout_ms(e::HTTP.TimeoutError) =
    hasproperty(e, :readtimeout) ? e.readtimeout * 1000 : e.timeout_ns ÷ 1_000_000

# Underlying cause of a connect error: `.error` on 1.x, `.cause` on 2.x.
_http_connect_cause(e::HTTP.ConnectError) = hasproperty(e, :cause) ? e.cause : e.error

# Message for a generic HTTP error. HTTP 2.x introduces a dedicated `HTTP.DNSError`
# (a subtype of HTTP.HTTPError) for name-resolution failures, where 1.x instead wraps a
# `Sockets.DNSError` inside a ConnectError. The two stringify differently
# (`"HTTP.DNSError(...)"` vs `"DNSError: ..."`); normalize the 2.x form so the surfaced
# reason starts with "DNSError" on both, keeping the message stable across versions.
_http_error_message(error::HTTP.HTTPError) = string(error)
@static if _HTTP_V2
    _http_error_message(error::HTTP.DNSError) = "DNSError: could not resolve host \"$(error.hostname)\""
end

# Inactivity-timeout keyword: 1.x calls it `readtimeout`; 2.0 renamed it to
# `read_idle_timeout` (`readtimeout` still works but emits a deprecation warning).
_http_read_timeout_kw(timeout) = _HTTP_V2 ? (; read_idle_timeout=timeout) : (; readtimeout=timeout)

function get_response_property(raw::HTTP.Response, name::Symbol)
    if name === :message
        return _http_statustext(raw)
    else
        return getproperty(raw, name)
    end
end

function get_response_header(resp::HTTP.Response, name::AbstractString, defaultval::AbstractString)
    return HTTP.header(resp, name, defaultval)
end

struct HTTPRequestError <: AbstractHTTPLibError
    message::String
    error::HTTP.HTTPError
    response::Union{Nothing,HTTP.Response}

    function HTTPRequestError(error::HTTP.TimeoutError, bytesread::Int, response::Union{Nothing,HTTP.Response})
        message = "Operation timed out after $(_http_timeout_ms(error)) milliseconds with $(bytesread) bytes received"
        new(message, error, response)
    end

    function HTTPRequestError(error::HTTP.TimeoutError, response::Union{Nothing,HTTP.Response})
        message = "Operation timed out after $(_http_timeout_ms(error)) milliseconds"
        new(message, error, response)
    end

    function HTTPRequestError(error::HTTP.ConnectError)
        cause = _http_connect_cause(error)
        message = if isa(cause, CapturedException)
            string(cause.ex)
        else
            string(cause)
        end
        new(message, error, nothing)
    end

    function HTTPRequestError(error::HTTP.HTTPError)
        message = _http_error_message(error)
        new(message, error, nothing)
    end
end

_http_as_request_error(args...) = nothing
_http_as_request_error(ex::HTTP.HTTPError, args...) = return HTTPRequestError(ex)
_http_as_request_error(ex::HTTP.ConnectError, args...) = return HTTPRequestError(ex)
_http_as_request_error(ex::HTTP.TimeoutError, args...) = return HTTPRequestError(ex, args...)
_http_as_request_error(ex::TaskFailedException, args...) = _http_as_request_error(ex.task.exception, args...)

function _http_as_request_error(ex::CompositeException, args...)
    for ex in ex.exceptions
        request_error = _http_as_request_error(ex, args...)
        if !isnothing(request_error)
            return request_error
        end
    end
    return nothing
end

get_response(error::HTTPRequestError) = error.response
function get_message(error::HTTPRequestError)
    return error.message
end
function get_status(error::HTTPRequestError)
    if isnothing(error.response)
        return 0
    else
        return error.response.status
    end
end

function prep_args(::Val{:http}, ctx::Ctx)
    kwargs = copy(ctx.client.clntoptions)

    isempty(ctx.file) && (ctx.body === nothing) && isempty(ctx.form) && !("Content-Length" in keys(ctx.header)) && (ctx.header["Content-Length"] = "0")
    headers = ctx.header
    body = nothing

    content_type_set = _header_value_ci(headers, "Content-Type")
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

    openhandles = Any[]
    try
        if !isempty(ctx.file) || (content_type_set == "multipart/form-data")
            if !isnothing(content_type_set) && content_type_set !== "multipart/form-data"
                throw(OpenAPIException("Content type already set to $content_type_set. To send file, it must be multipart/form-data."))
            end

            body_dict = Dict{String,Any}()

            for (_k,_v) in ctx.file
                if isfile(_v)
                    fhandle = open(_v)
                    push!(openhandles, fhandle)
                    body_dict[_k] = fhandle
                else
                    body_dict[_k] = HTTP.Multipart(_k, IOBuffer(_v))
                end
            end

            for (_k,_v) in ctx.form
                body_dict[_k] = _v
            end
            body = HTTP.Form(body_dict)
            headers["Content-Type"] = content_type_set = _http_form_content_type(body)
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
        kwargs[:openhandles] = openhandles
    catch
        # if prep_args fails after opening handles, ensure they are closed
        for fhandle in openhandles
            close(fhandle)
        end
        rethrow()
    end

    return body, kwargs
end

function do_request(::Val{:http}, ctx::Ctx, resource_path::String, body, output, kwargs, stream::Bool=false; stream_to::Union{Channel,Nothing}=nothing)
    method = kwargs[:method]
    timeout_secs = kwargs[:timeout]
    openhandles = kwargs[:openhandles]
    headers_dict = kwargs[:headers]
    headers = [k => v for (k, v) in headers_dict]
    bytesread = Ref{Int}(0)
    captured_response = Ref{Union{Nothing,HTTP.Response}}(nothing)

    if body === nothing
        body = UInt8[]
    end

    try
        if stream
            return _http_streaming_request(ctx, method, resource_path, headers, body, timeout_secs, bytesread, captured_response, output, stream_to)
        else
            return _http_request(ctx, method, resource_path, headers, body, timeout_secs, bytesread, captured_response, output)
        end
    catch ex
        possible_request_error = _http_as_request_error(ex, bytesread[], captured_response[])
        if !isnothing(possible_request_error)
            return possible_request_error, output
        else
            rethrow(ex)
        end
    finally
        for fhandle in openhandles
            close(fhandle)
        end
    end
end

function _http_request(ctx, method, url, headers, body, timeout, bytesread, captured_response, output)
    captured_response[] = http_response = HTTP.request(method, url, headers, body;
                           _http_read_timeout_kw(timeout)...,
                           connect_timeout=timeout ÷ 2,
                           retry=false,
                           redirect=true,
                           status_exception=false,
                           verbose=get(ctx.client.clntoptions, :verbose, false))

    bytesread[] += write(output, http_response.body)
    close(output)

    return http_response, output
end

function _http_streaming_request(ctx, method, url, headers, body, timeout, bytesread, captured_response, output, stream_to)
    http_response = nothing

    # HTTP.jl 2.0's `HTTP.open` does not accept a `verbose` keyword; only pass it on 1.x.
    open_kwargs = merge(_http_read_timeout_kw(timeout),
                        (; connect_timeout=timeout ÷ 2,
                           retry=false,
                           redirect=true,
                           status_exception=false))
    if !_HTTP_V2
        open_kwargs = merge(open_kwargs, (; verbose=get(ctx.client.clntoptions, :verbose, false)))
    end

    # Capture the streaming connection so the abort-on-close watcher below can
    # unblock the read task when the consumer closes `stream_to`. (Mirrors the
    # `:downloads` backend, which interrupts its download task on channel close.)
    io_ref = Ref{Any}(nothing)

    @sync begin
        read_task = @async begin
            try
                HTTP.open(method, url, headers; open_kwargs...) do io
                    io_ref[] = io
                    write(io, body)
                    captured_response[] = http_response = startread(io)
                    try
                        # `read(io, n)` is unavailable on 2.0 streams; read into a reusable
                        # buffer with `readbytes!`, which works on both 1.x and 2.x.
                        buf = Vector{UInt8}(undef, 8192)  # 8KB chunks
                        while !eof(io)
                            n = readbytes!(io, buf)
                            n == 0 && break
                            bytesread[] += write(output, view(buf, 1:n))
                        end
                    finally
                        close(output)
                    end
                end
            catch ex
                close(output)
                # When the consumer closes `stream_to`, the watcher task below aborts
                # this read (close(io) + a scheduled InterruptException); that surfaces
                # here as an IO error or InterruptException. Swallow it so the streaming
                # request returns normally instead of propagating a spurious error. A
                # read timeout or genuine network error arrives while `stream_to` is
                # still open (and is not our InterruptException), so it still throws.
                if isopen(stream_to) && !isa(ex, InterruptException)
                    rethrow(ex)
                end
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
                    data = response(return_type, nothing, chunk)  # resp not available yet in streaming
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
            # Abort-on-close watcher: when the consumer closes `stream_to` (e.g. a
            # k8s watch is stopped via `close(stream)`), abort the read task above so
            # it unblocks immediately instead of hanging on the socket until the
            # read-idle timeout. Mirrors the `:downloads` backend, which interrupts
            # its download task on channel close.
            try
                while isopen(stream_to)
                    wait(stream_to)
                    yield()
                end
            catch ex
                isa(ex, InvalidStateException) || rethrow(ex)
            end
            # Best-effort close of the connection. On HTTP/2 this alone does NOT wake a
            # body read parked on the flow-control timer, so we also forcibly interrupt
            # the read task (as `:downloads` does for non-interruptible downloads).
            io = io_ref[]
            # `io` may be `nothing` if the consumer closed before the connection was
            # established; in practice a consumer only stops after receiving an event
            # (or a timer fires seconds later), so the connection is already up. This
            # is the same theoretical hole the `:downloads` watcher has.
            if io !== nothing
                try
                    close(io)
                catch
                    # already closed / natural EOF — nothing to abort
                end
            end
            # `stream_to` also closes on natural EOF (the chunk reader closes it after
            # the read task finishes); the `istaskdone` guard skips the interrupt in
            # that case. For JuliaRun's watch consumers an interrupt of an already-
            # finishing read is harmless anyway — it maps to `is_request_interrupted`,
            # the same signal a read-idle timeout produces, which they already retry on.
            if !istaskdone(read_task)
                schedule(read_task, InterruptException(); error=true)
            end
        end
    end

    return http_response, output
end
