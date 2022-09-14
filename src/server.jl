module Servers

using JSON

import ..OpenAPI: APIModel, ValidationException, from_json

# const OpenAPIParams = :openapi_params

function middleware(read, validate, invoke; init=nothing, pre_validation=nothing, pre_invoke=nothing, post_invoke=nothing)
    ret = (init === nothing) ? read : init |> read
    ret = (pre_validation === nothing) ? ret |> validate : ret |> pre_validation |> validate
    ret = (pre_invoke === nothing) ? ret |> invoke : ret |> pre_invoke |> invoke
    if post_invoke !== nothing
        ret = ret |> post_invoke
    end

    return ret
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

function to_param_type(::Type{Vector{T}}, strval::String, delim::String) where {T}
    elems = strip.(split(strval, delim))
    return map(x->to_param_type(T, x), elems)
end

function to_param(T, source::Dict, name::String; required::Bool=false, collection_format::Union{String,Nothing}=nothing, multipart::Bool=false, isfile::Bool=false)
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

end # module Servers