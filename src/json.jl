# Declare how StructTypes should handle APIModels
StructTypes.StructType(::Type{<:APIModel}) = StructTypes.Struct()

# This single line replaces the entire JSONWrapper implementation.
# It tells JSON.jl to automatically omit fields whose values are `nothing`.
StructTypes.omitempties(::Type{<:APIModel}) = true

# This hook tells JSON.read to use our custom `from_json` logic
# for constructing APIModel types. This preserves our handling of dates,
# discriminated unions, and other special cases.
StructTypes.construct(::Type{T}, dict::Dict) where {T <: APIModel} = from_json(T, dict)


# The `lower` method for UnionAPIModel is still useful because it allows us to
# serialize the inner .value of a oneOf/anyOf type, not the wrapper itself.
# JSON.jl v1.0 still respects `lower`.

function lower(o::T) where {T<:UnionAPIModel}
    if typeof(o.value) <: APIModel
        # Use JSON.lower on the wrapped value to apply its own rules
        return JSON.lower(o.value)
    elseif typeof(o.value) <: Union{String,Real}
        return o.value
    else
        return to_json(o.value)
    end
end

struct StyleCtx
    location::Symbol
    name::String
    is_explode::Bool
end

is_deep_explode(sctx::StyleCtx) = sctx.name == "deepObject" && sctx.is_explode

function deep_object_to_array(src::Dict)
    keys_are_int = all(key -> occursin(r"^\d+$", key), keys(src))
    if keys_are_int
        sorted_keys = sort(collect(keys(src)), by=x->parse(Int, x))
        final = []
        for key in sorted_keys
            push!(final, src[key])
        end
        return final
    else
        src
    end
end

to_json(o) = JSON.json(o)

from_json(::Type{Union{Nothing,T}}, json::Dict{String,Any}; stylectx=nothing) where {T} = from_json(T, json; stylectx)
from_json(::Type{Union{Nothing,T}}, json::JSON.Object{String, Any}; stylectx=nothing) where {T} = from_json(T, json; stylectx)

from_json(::Type{T}, json::Dict{String,Any}; stylectx=nothing) where {T} = from_json(T(), json; stylectx)
from_json(::Type{T}, json::JSON.Object{String, Any}; stylectx=nothing) where {T} = from_json(T(), json; stylectx)

from_json(::Type{T}, json::Dict{String,Any}; stylectx=nothing) where {T <: Dict} = convert(T, json)
from_json(::Type{T}, json::JSON.Object{String, Any}; stylectx=nothing) where {T <: Dict} = convert(T, json)

from_json(::Type{T}, j::Dict{String,Any}; stylectx=nothing) where {T <: String} = to_json(j)
from_json(::Type{T}, j::JSON.Object{String, Any}; stylectx=nothing) where {T <: String} = to_json(j)

from_json(::Type{Any}, j::Dict{String,Any}; stylectx=nothing) = j
from_json(::Type{Any}, j::JSON.Object{String, Any}; stylectx=nothing) = j

from_json(::Type{Vector{T}}, j::Vector{Any}; stylectx=nothing) where {T} = j

function from_json(::Type{Vector{T}}, json::Dict{String, Any}; stylectx=nothing) where {T}
    if !isnothing(stylectx) && is_deep_explode(stylectx)
        cvt = deep_object_to_array(json)
        if isa(cvt, Vector)
            return from_json(Vector{T}, cvt; stylectx)
        else
            return from_json(T, json; stylectx)
        end
    else
        return from_json(T, json; stylectx)
    end
end

function from_json(::Type{Vector{T}}, json::JSON.Object{String, Any}; stylectx=nothing) where {T}
    if !isnothing(stylectx) && is_deep_explode(stylectx)
        cvt = deep_object_to_array(json)
        if isa(cvt, Vector)
            return from_json(Vector{T}, cvt; stylectx)
        else
            return from_json(T, json; stylectx)
        end
    else
        return from_json(T, json; stylectx)
    end
end

function from_json(o::T, json::Dict{String,Any};stylectx=nothing) where {T <: UnionAPIModel}
    return from_json(o, :value, json;stylectx)
end

function from_json(o::T, json::JSON.Object{String, Any};stylectx=nothing) where {T <: UnionAPIModel}
    return from_json(o, :value, json;stylectx)
end

from_json(::Type{T}, val::Union{String,Real};stylectx=nothing) where {T <: UnionAPIModel} = T(val)
function from_json(o::T, val::Union{String,Real};stylectx=nothing) where {T <: UnionAPIModel}
    o.value = val
    return o
end

function from_json(o::T, json::Dict{String,Any};stylectx=nothing) where {T <: APIModel}
    jsonkeys = [Symbol(k) for k in keys(json)]
    for name in intersect(propertynames(o), jsonkeys)
        from_json(o, name, json[String(name)];stylectx)
    end
    return o
end

function from_json(o::T, json::JSON.Object{String, Any};stylectx=nothing) where {T <: APIModel}
    jsonkeys = [Symbol(k) for k in collect(keys(json))]
    for name in intersect(propertynames(o), jsonkeys)
        from_json(o, name, json[String(name)];stylectx)
    end
    return o
end

function from_json(o::T, name::Symbol, json::Dict{String,Any};stylectx=nothing) where {T <: APIModel}
    ftype = (T <: UnionAPIModel) ? property_type(T, name, json) : property_type(T, name)
    fval = from_json(ftype, json; stylectx)
    setfield!(o, name, convert(ftype, fval))
    return o
end

function from_json(o::T, name::Symbol, json::JSON.Object{String, Any};stylectx=nothing) where {T <: APIModel}
    ftype = (T <: UnionAPIModel) ? property_type(T, name, json) : property_type(T, name)
    fval = from_json(ftype, json; stylectx)
    setfield!(o, name, convert(ftype, fval))
    return o
end

function from_json(o::T, name::Symbol, v; stylectx=nothing) where {T <: APIModel}
    ftype = (T <: UnionAPIModel) ? property_type(T, name, Dict{String,Any}()) : property_type(T, name)
    atype = isa(ftype, Union) ? ((ftype.a === Nothing) ? ftype.b : ftype.a) : ftype
    if ftype === Any
        setfield!(o, name, v)
    elseif ZonedDateTime <: ftype
        setfield!(o, name, str2zoneddatetime(v))
    elseif DateTime <: ftype
        setfield!(o, name, str2datetime(v))
    elseif Date <: ftype
        setfield!(o, name, str2date(v))
    elseif String <: ftype && isa(v, Real)
        # string numbers can have format specifiers that allow numbers, ensure they are converted to strings
        setfield!(o, name, string(v))
    elseif atype <: Real && isa(v, AbstractString)
        setfield!(o, name, parse(atype, v))
    else
        setfield!(o, name, convert(ftype, v))
    end
    return o
end

function from_json(o::T, name::Symbol, v::Vector; stylectx=nothing) where {T <: APIModel}
    # in Julia we can not support JSON null unless the element type is explicitly set to support it
    ftype = property_type(T, name)

    if ftype === Any
        setfield!(o, name, v)
        return o
    end

    vtype = isa(ftype, Union) ? ((ftype.a === Nothing) ? ftype.b : ftype.a) : (ftype <: Vector) ? ftype : Union{}
    veltype = eltype(vtype)
    (Nothing <: veltype) || filter!(x->x!==nothing, v)

    if veltype === Any
        setfield!(o, name, convert(ftype, v))
    elseif ZonedDateTime <: veltype
        setfield!(o, name, map(str2zoneddatetime, v))
    elseif DateTime <: veltype
        setfield!(o, name, map(str2datetime, v))
    elseif Date <: veltype
        setfield!(o, name, map(str2date, v))
    else
        if (vtype <: Vector) && (veltype <: OpenAPI.UnionAPIModel)
            vec = veltype[]
            for vecelem in v
                push!(vec, from_json(veltype(), :value, vecelem;stylectx))
            end
            setfield!(o, name, vec)
        elseif (vtype <: Vector) && (veltype <: OpenAPI.APIModel)
            setfield!(o, name, map(x->convert(veltype,x), v))
        elseif (vtype <: Vector) && (veltype <: String)
            # ensure that elements are converted to String
            # convert is to do the translation to Union{Nothing,String} when necessary
            setfield!(o, name, convert(ftype, map(string, v)))
        elseif ftype <: OpenAPI.UnionAPIModel
            setfield!(o, name, ftype(v))
        else
            setfield!(o, name, convert(ftype, v))
        end
    end
    return o
end

function from_json(o::T, name::Symbol, ::Nothing;stylectx=nothing) where {T <: APIModel}
    setfield!(o, name, nothing)
    return o
end
