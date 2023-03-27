module Servers

using JSON
using HTTP

import ..OpenAPI: APIModel, ValidationException, from_json, to_json
import HTTP.Messages: hasheader, setheader, header

function middleware(impl, read, validate, invoke;
        init=nothing,
        pre_validation=nothing,
        pre_invoke=nothing,
        post_invoke=nothing
    )
    handler = req -> (invoke(impl; post_invoke=post_invoke))(req)
    if !isnothing(pre_invoke)
        handler = pre_invoke(handler)
    end
    handler = validate(handler)
    if !isnothing(pre_validation)
        handler = pre_validation(handler)
    end
    handler = read(handler)
    if !isnothing(init)
        handler = init(handler)
    end
    return handler
end

##############################
# server parameter conversions
##############################
function get_param(source::Dict, name::String, required::Bool)
    val = get(source, name, nothing)
    if required && isnothing(val)
        throw(ValidationException("required parameter \"$name\" missing"))
    end
    return val
end

function to_param_type(::Type{T}, strval::String) where {T <: Number}
    parse(T, strval)
end

to_param_type(::Type{T}, val::T) where {T} = val
to_param_type(::Type{T}, ::Nothing) where {T} = nothing
to_param_type(::Type{String}, val::Vector{UInt8}) = String(copy(val))
to_param_type(::Type{Vector{UInt8}}, val::String) = convert(Vector{UInt8}, copy(codeunits(val)))

function to_param_type(::Type{T}, strval::String) where {T <: APIModel}
    from_json(T, JSON.parse(strval))
end

function to_param_type(::Type{T}, json::Dict{String,Any}) where {T <: APIModel}
    from_json(T, json)
end

function to_param_type(::Type{Vector{T}}, strval::String, delim::String) where {T}
    elems = string.(strip.(split(strval, delim)))
    return map(x->to_param_type(T, x), elems)
end

function to_param_type(::Type{Vector{T}}, strval::String) where {T}
    elems = JSON.parse(strval)
    return map(x->to_param_type(T, x), elems)
end

function to_param(T, source::Dict, name::String; required::Bool=false, collection_format::Union{String,Nothing}=",", multipart::Bool=false, isfile::Bool=false)
    param = get_param(source, name, required)
    if param === nothing
        return nothing
    end
    if multipart
        # param is a Multipart
        param = isfile ? param.data : String(param.data)
    end
    if T <: Vector
        return to_param_type(T, param, collection_format)
    else
        return to_param_type(T, param)
    end
end

function is_any_mime_accepted(mime_type::AbstractString)
    parts = first(strip.(split(mime_type, ";")))
    if parts == "*/*"
        return true
    end
    return false
end

# json if it is of the format `.*/json[;.*]` (roughly)
function is_json_mime_accepted(mime_type::AbstractString)
    parts = first(strip.(split(mime_type, ";")))
    parts = strip.(split(parts, "/"))
    return (length(parts) == 2) && (parts[2] == "json")
end

# text if it is of the format `text/.*[;.*]` (roughly)
function is_text_mime_accepted(mime_type::AbstractString)
    parts = first(strip.(split(mime_type, ";")))
    parts = strip.(split(parts, "/"))
    return (length(parts) == 2) && (parts[1] == "text")
end

server_response(resp::HTTP.Response) = resp
server_response(::Nothing) = server_response("")
server_response(ret) = server_response(to_json(ret))
server_response(resp::String) = HTTP.Response(200, resp)

function server_response(req::HTTP.Request, resp::HTTP.Response)
    if !hasheader(resp, "X-Request-Id") && hasheader(req, "X-Request-Id")
        setheader(resp, "X-Request-Id" => header(req, "X-Request-Id"))
    end
    return resp
end
server_response(req::HTTP.Request, ::Nothing) = server_response(req, "")
function server_response(req::HTTP.Request, ret; content_type=nothing)
    !isnothing(content_type) && isempty(content_type) && (content_type = nothing)
    if isnothing(content_type)
        accepted_mime_types = strip.(split(header(req, "Accept", "*/*"), ","))
        # try to detect a json mime type
        if any(is_any_mime_accepted, accepted_mime_types)
            content_type = "application/json"
        else
            for mime in accepted_mime_types
                if is_json_mime_accepted(mime)
                    content_type = mime
                    break
                end
            end
            # if no json accept type was detected, fall through to text
        end
    end

    server_response(req, to_json(ret); content_type=content_type)
end

function server_response(req::HTTP.Request, resp::String; content_type=nothing)
    httpresp = HTTP.Response(200, resp)
    if !isempty(resp)
        !isnothing(content_type) && isempty(content_type) && (content_type = nothing)
        if isnothing(content_type)
            accepted_mime_types = strip.(split(header(req, "Accept", "*/*"), ","))
            # try to detect a text mime type
            if any(is_any_mime_accepted, accepted_mime_types)
                content_type = "text/plain"
            else
                for mime in accepted_mime_types
                    if is_text_mime_accepted(mime)
                        content_type = mime
                        break
                    end
                end
            end
        end
        # respond with content type if only we could detect one
        if !isnothing(content_type)
            HTTP.Messages.setheader(httpresp, "Content-Type" => content_type)
        end
    end
    return server_response(req, httpresp)
end

end # module Servers