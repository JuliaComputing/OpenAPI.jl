module Servers

using JSON
using HTTP

import ..OpenAPI: APIModel, ValidationException, from_json, to_json

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

server_response(resp::HTTP.Response) = resp
server_response(::Nothing) = server_response("")
server_response(ret) = server_response(to_json(ret))
server_response(resp::String) = HTTP.Response(200, resp)

end # module Servers