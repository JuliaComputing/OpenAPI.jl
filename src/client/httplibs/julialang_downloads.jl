# =============================================================================
# Downloads.jl Backend Implementation
# =============================================================================
# This file implements the HTTP client backend using the Downloads.jl library.
#
# Dependencies:
#   - Downloads (stdlib): Primary HTTP client library
#   - LibCURL: For low-level cURL operations (file uploads, MIME handling)
#   - URIs: For URI escaping and query parameter handling
#
# Public Interface (via Val dispatch):
#   - prep_args(::Val{:downloads}, ctx::Ctx)
#   - do_request(::Val{:downloads}, ctx, ...)
#
# Type-Specific Methods:
#   - get_response_header(::Downloads.Response, ...)
#   - get_message(::Downloads.RequestError)
#   - get_response(::Downloads.RequestError)
#   - get_status(::Downloads.RequestError)
# =============================================================================

function _downloads_get_content_type(headers::Dict{String,String})
    for (name, value) in headers
        if lowercase(name) == "content-type"
            return value
        end
    end
    return nothing
end

function prep_args(::Val{:downloads}, ctx::Ctx)
    kwargs = copy(ctx.client.clntoptions)
    kwargs[:downloader] = ctx.client.downloader     # use the default downloader for most cases

    isempty(ctx.file) && (ctx.body === nothing) && isempty(ctx.form) && !("Content-Length" in keys(ctx.header)) && (ctx.header["Content-Length"] = "0")
    headers = ctx.header
    body = nothing

    content_type_set = _downloads_get_content_type(headers)
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

function get_response_header(resp::Downloads.Response, name::AbstractString, defaultval::AbstractString)
    for (n,v) in resp.headers
        (lowercase(n) == lowercase(name)) && (return v)
    end
    return defaultval
end

function get_message(error::Downloads.RequestError)
    reason = error.message
    isempty(reason) && (reason = error.response.message)
    return reason
end

function get_response(error::Downloads.RequestError)
    return error.response
end

function get_status(error::Downloads.RequestError)
    return error.response.status
end

function do_request(::Val{:downloads}, ctx::Ctx, resource_path::String, body, output, kwargs, stream::Bool=false; stream_to::Union{Channel,Nothing}=nothing)
    resp = nothing
    try
        input = nothing
        if body !== nothing
            input = PipeBuffer()
            write(input, body)
        end

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
