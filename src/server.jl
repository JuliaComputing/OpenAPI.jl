module Servers

using JSON
using HTTP

import ..OpenAPI: APIModel, ValidationException, from_json, to_json, deep_object_to_array, StyleCtx, is_deep_explode

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
struct Param
    keylist::Vector{String}
    value::String
end

function parse_query_dict(query_dict::Dict{String, String})::Vector{Param}
    params = Vector{Param}()
    for (key, value) in query_dict
        keylist = replace.(split(key, "["), "]"=>"")
        push!(params, Param(keylist, value))
    end

    return params
end

function convert_to_dict(params::Vector{Param})::Dict{String, Any}
    deserialized_dict = Dict{String, Any}()

    for param in params
        current = deserialized_dict
        for part in param.keylist[1:end-1]
            current = get!(current, part, Dict{String, Any}())
        end
        current[param.keylist[end]] = param.value
    end
    return deserialized_dict
end

function deep_dict_repr(qp::Dict)
    convert_to_dict(parse_query_dict(qp))
end

function get_param(source::Dict, name::String, required::Bool)
    val = get(source, name, nothing)
    if required && isnothing(val)
        throw(ValidationException("required parameter \"$name\" missing"))
    end
    return val
end

function get_param(source::Vector{HTTP.Forms.Multipart}, name::String, required::Bool)
    ind = findfirst(x -> x.name == name, source)
    if required && isnothing(ind)
        throw(ValidationException("required parameter \"$name\" missing"))
    elseif isnothing(ind)
        return nothing
    else
        return source[ind]
    end
end

function to_param_type(::Type{T}, strval::String; stylectx=nothing) where {T <: Number}
    parse(T, strval)
end

to_param_type(::Type{T}, val::T; stylectx=nothing) where {T} = val
to_param_type(::Type{T}, ::Nothing; stylectx=nothing) where {T} = nothing
to_param_type(::Type{String}, val::Vector{UInt8}; stylectx=nothing) = String(copy(val))
to_param_type(::Type{Vector{UInt8}}, val::String; stylectx=nothing) = convert(Vector{UInt8}, copy(codeunits(val)))
to_param_type(::Type{Vector{T}}, val::Vector{T}, _collection_format::Union{String,Nothing}; stylectx=nothing) where {T} = val
to_param_type(::Type{Vector{T}}, json::Vector{Any}; stylectx=nothing) where {T} = [to_param_type(T, x; stylectx) for x in json]

function to_param_type(::Type{Vector{T}}, json::Dict{String, Any}; stylectx=nothing) where {T}
    if !isnothing(stylectx) && is_deep_explode(stylectx)
        cvt = deep_object_to_array(json)
        if isa(cvt, Vector)
            return to_param_type(Vector{T}, cvt; stylectx)
        end
    end
    error("Unable to convert $json to $(Vector{T})")
end

function to_param_type(::Type{T}, strval::String; stylectx=nothing) where {T <: APIModel}
    from_json(T, JSON.parse(strval); stylectx)
end

function  to_param_type(::Type{T}, json::Dict{String,Any}; stylectx=nothing) where {T <: APIModel}
    from_json(T, json; stylectx)
end

function to_param_type(::Type{Vector{T}}, strval::String, delim::String; stylectx=nothing) where {T}
    elems = string.(strip.(split(strval, delim)))
    return map(x->to_param_type(T, x; stylectx), elems)
end

function to_param_type(::Type{Vector{T}}, strval::String; stylectx=nothing) where {T}
    elems = JSON.parse(strval)
    return map(x->to_param_type(T, x; stylectx), elems)
end

function to_param(T, source::Dict, name::String; required::Bool=false, collection_format::Union{String,Nothing}=",", multipart::Bool=false, isfile::Bool=false, style::String="form", is_explode::Bool=true)
    deep_explode = style == "deepObject" && is_explode
    if deep_explode
        source = deep_dict_repr(source)
    end
    param = get_param(source, name, required)
    if param === nothing
        return nothing
    end
    if multipart
        # param is a Multipart
        param = isfile ? param.data : String(param.data)
    end
    if deep_explode
        return to_param_type(T, param; stylectx=StyleCtx(style, is_explode))
    end
    if T <: Vector
        to_param_type(T, param, collection_format)
    else
        to_param_type(T, param)
    end
end

function to_param(T, source::Vector{HTTP.Forms.Multipart}, name::String; required::Bool=false, collection_format::Union{String,Nothing}=",", multipart::Bool=false, isfile::Bool=false)
    param = get_param(source, name, required)
    if param === nothing
        return nothing
    end
    if multipart
        # param is a Multipart
        param = isfile ? take!(param.data) : String(take!(param.data))
    end
    if T <: Vector
        return to_param_type(T, param, collection_format)
    else
        return to_param_type(T, param)
    end
end

function HTTP.Response(code::Integer, o::APIModel)
    return HTTP.Response(code, [Pair("Content-Type", "application/json")], to_json(o))
end

server_response(resp::HTTP.Response) = resp
server_response(::Nothing) = server_response("")
server_response(ret) =
    server_response(to_json(ret), [Pair("Content-Type", "application/json")])
server_response(resp::AbstractString, headers=HTTP.Headers()) =
    HTTP.Response(200, headers, body=resp)

end # module Servers
