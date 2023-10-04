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
function lower(o::T) where {T<:UnionAPIModel}
    if typeof(o.value) <: APIModel
        return JSONWrapper(o.value)
    elseif typeof(o.value) <: Union{String,Real}
        return o.value
    else
        return to_json(o.value)
    end
end

to_json(o) = JSON.json(o)

from_json(::Type{Union{Nothing,T}}, json::Dict{String,Any}) where {T} = from_json(T, json)
from_json(::Type{T}, json::Dict{String,Any}) where {T} = from_json(T(), json)
from_json(::Type{T}, json::Dict{String,Any}) where {T <: Dict} = convert(T, json)
from_json(::Type{T}, j::Dict{String,Any}) where {T <: String} = to_json(j)
from_json(::Type{Any}, j::Dict{String,Any}) = j

function from_json(o::T, json::Dict{String,Any}) where {T <: UnionAPIModel}
    return from_json(o, :value, json)
end

from_json(::Type{T}, val::Union{String,Real}) where {T <: UnionAPIModel} = T(val)
function from_json(o::T, val::Union{String,Real}) where {T <: UnionAPIModel}
    o.value = val
    return o
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
    ftype = (T <: UnionAPIModel) ? property_type(T, name, Dict{String,Any}()) : property_type(T, name)
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
    else
        setfield!(o, name, convert(ftype, v))
    end
    return o
end

function from_json(o::T, name::Symbol, v::Vector) where {T <: APIModel}
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
                push!(vec, from_json(veltype(), :value, vecelem))
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

function from_json(o::T, name::Symbol, ::Nothing) where {T <: APIModel}
    setfield!(o, name, nothing)
    return o
end