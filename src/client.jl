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

include("client/clienttypes.jl")
include("client/chunk_readers.jl")
include("client/httplibs/httplibs.jl")

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

prep_args(ctx::Ctx) = prep_args(Val(ctx.client.httplib), ctx)

response(::Type{Nothing}, resp::HTTPLibResponse, body) = nothing::Nothing
response(::Type{T}, resp::HTTPLibResponse, body) where {T <: Real} = response(T, body)::T
response(::Type{T}, resp::HTTPLibResponse, body) where {T <: String} = response(T, body)::T
function response(::Type{T}, resp::HTTPLibResponse, body) where {T}
    ctype = get_response_header(resp, "Content-Type", "application/json")
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

    if stream
        @assert stream_to !== nothing
    end

    output = Base.BufferStream()
    resp, output = do_request(Val(ctx.client.httplib), ctx, resource_path, body, output, kwargs, stream; stream_to=stream_to)

    return resp, output
end

function exec(ctx::Ctx, stream_to::Union{Channel,Nothing}=nothing)
    stream = stream_to !== nothing
    resp, output = do_request(ctx, stream; stream_to=stream_to)

    if resp === nothing
        # request was interrupted
        throw(InvocationException("request was interrupted"))
    end

    if isa(resp, HTTPLibError)
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
    # All client library wrappers ensure that the reason string format is the same for longpoll timeouts
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
    extract_filename(resp)::String

Extracts the filename from the `Content-Disposition` header of the HTTP response.
If not found, then creates a filename from the `Content-Type` header.
"""
extract_filename(resp::ApiResponse) = extract_filename(resp.raw)
function extract_filename(resp::HTTPLibResponse)::String
    # attempt to extract filename from content-disposition header
    content_disposition_str = get_response_header(resp, "content-disposition", "")
    m = match(content_disposition_re, content_disposition_str)
    if !isnothing(m) && !isempty(m.captures) && !isnothing(m.captures[1])
        return m.captures[1]
    end

    # attempt to create a filename from content-type header
    content_type_str = get_response_header(resp, "content-type", "")
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
