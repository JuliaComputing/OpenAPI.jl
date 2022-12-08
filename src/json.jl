# JSONWrapper for OpenAPI models handles
# - null fields
# - field names that are Julia keywords
struct JSONWrapper{T<:APIModel} <: AbstractDict{Symbol, Any}
    wrapped::T
    flds::Tuple
end

JSONWrapper(o::T) where {T<:APIModel} = JSONWrapper(o, filter(n->hasproperty(o,n) && (getproperty(o,n) !== nothing), propertynames(o)))

getindex(w::JSONWrapper, s::Symbol) = getproperty(w.wrapped, s)
keys(w::JSONWrapper) = w.flds
length(w::JSONWrapper) = length(w.flds)

function iterate(w::JSONWrapper, state...)
    result = iterate(w.flds, state...)
    if result === nothing
        return result
    else
        name,nextstate = result
        val = getproperty(w.wrapped, name)
        return (name=>val, nextstate)
    end
end

lower(o::T) where {T<:APIModel} = JSONWrapper(o)
lower(o::T) where {T<:UnionAPIModel} = JSONWrapper(o.value)

to_json(o) = JSON.json(o)

from_json(::Type{Union{Nothing,T}}, json::Dict{String,Any}) where {T} = from_json(T, json)
from_json(::Type{T}, json::Dict{String,Any}) where {T} = from_json(T(), json)
from_json(::Type{T}, json::Dict{String,Any}) where {T <: Dict} = convert(T, json)
from_json(::Type{T}, j::Dict{String,Any}) where {T <: String} = to_json(j)
from_json(::Type{Any}, j::Dict{String,Any}) = j

function from_json(o::T, json::Dict{String,Any}) where {T <: UnionAPIModel}
    return from_json(o, :value, json)
end

function from_json(o::T, json::Dict{String,Any}) where {T <: APIModel}
    jsonkeys = [Symbol(k) for k in keys(json)]
    for name in intersect(propertynames(o), jsonkeys)
        from_json(o, name, json[String(name)])
    end
    return o
end

function from_json(o::T, name::Symbol, json::Dict{String,Any}) where {T <: APIModel}
    ftype = (T <: UnionAPIModel) ? property_type(T, name, json) : property_type(T, name)
    fval = from_json(ftype, json)
    setfield!(o, name, convert(ftype, fval))
    return o
end

function from_json(o::T, name::Symbol, v) where {T <: APIModel}
    ftype = property_type(T, name)
    if ZonedDateTime <: ftype
        setfield!(o, name, str2zoneddatetime(v))
    elseif DateTime <: ftype
        setfield!(o, name, str2datetime(v))
    elseif Date <: ftype
        setfield!(o, name, str2date(v))
    else
        setfield!(o, name, convert(ftype, v))
    end
    return o
end

function from_json(o::T, name::Symbol, v::Vector) where {T <: APIModel}
    # in Julia we can not support JSON null unless the element type is explicitly set to support it
    ftype = property_type(T, name)
    vtype = isa(ftype, Union) ? ((ftype.a === Nothing) ? ftype.b : ftype.a) : (ftype <: Vector) ? ftype : Union{}
    veltype = eltype(vtype)
    (Nothing <: veltype) || filter!(x->x!==nothing, v)

    if ZonedDateTime <: veltype
        setfield!(o, name, map(str2zoneddatetime, v))
    elseif DateTime <: veltype
        setfield!(o, name, map(str2datetime, v))
    elseif Date <: veltype
        setfield!(o, name, map(str2date, v))
    else
        setfield!(o, name, convert(ftype, v))
    end
    return o
end

function from_json(o::T, name::Symbol, ::Nothing) where {T <: APIModel}
    setfield!(o, name, nothing)
    return o
end