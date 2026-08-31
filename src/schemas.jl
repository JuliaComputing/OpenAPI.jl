# Julia type -> JSON Schema (2020-12 dialect, as used by OpenAPI 3.1+).
# Named struct types are registered once under #/components/schemas and
# referenced by $ref everywhere they appear.

"""
    obj(pairs::Pair...) -> JSON.Object{String,Any}

An ordered JSON object from key-value pairs; keys convert to `String`. A small
helper for assembling OpenAPI document fragments by hand alongside
[`OpenAPI.document`](@ref).
"""
function obj(pairs::Pair...)
    o = JSON.Object{String,Any}()
    for (k, v) in pairs
        o[String(k)] = v
    end
    return o
end

emptyschema() = JSON.Object{String,Any}()  # {} matches any value

"""
Accumulates `#/components/schemas` entries while a document is built. Named
Julia struct types are registered once (by `nameof`, deduped) and referenced.
"""
struct SchemaRegistry
    schemas::JSON.Object{String,Any}
    seen::IdDict{Any,String}
end
SchemaRegistry() = SchemaRegistry(JSON.Object{String,Any}(), IdDict{Any,String}())

uniontypes(T) = T isa Union ? [uniontypes(T.a); uniontypes(T.b)] : [T]

"""
    schemaof(registry, T) -> JSON.Object

The JSON Schema for a Julia type. Primitives map directly; `Union`s become
`oneOf` (with `Union{Nothing, T}` including a null schema); `Vector`/`Dict`
map to arrays/objects; `NamedTuple`s become inline object schemas; named
structs are registered in the components registry and referenced with `\$ref`;
`Any` and abstract types become the empty (match-anything) schema.
"""
function schemaof(reg::SchemaRegistry, ::Type{T}) where {T}
    T === Any && return emptyschema()
    T === Nothing && return obj("type" => "null")
    T === Missing && return obj("type" => "null")
    T === Bool && return obj("type" => "boolean")
    T === Int64 && return obj("type" => "integer", "format" => "int64")
    T === Int32 && return obj("type" => "integer", "format" => "int32")
    T <: Integer && return obj("type" => "integer")
    T === Float64 && return obj("type" => "number", "format" => "double")
    T <: Real && return obj("type" => "number")
    T === Dates.Date && return obj("type" => "string", "format" => "date")
    T === Dates.DateTime && return obj("type" => "string", "format" => "date-time")
    T === Dates.Time && return obj("type" => "string", "format" => "time")
    (T <: AbstractString || T === Symbol || T === Char) && return obj("type" => "string")
    T isa Union && return obj("oneOf" => Any[schemaof(reg, t) for t in uniontypes(T)])
    T <: Base.Enum &&
        return obj("type" => "string", "enum" => Any[string(i) for i in instances(T)])
    T <: AbstractVector &&
        return obj("type" => "array", "items" => schemaof(reg, eltype(T)))
    T <: AbstractDict &&
        return obj("type" => "object", "additionalProperties" => schemaof(reg, valtype(T)))
    T <: Tuple && return obj("type" => "array")
    T <: NamedTuple && isconcretetype(T) && return objectschema(reg, T)
    if isstructtype(T) && isconcretetype(T)
        name = get(reg.seen, T, nothing)
        if name === nothing
            name = string(nameof(T))
            i = 2
            while haskey(reg.schemas, name)
                name = string(nameof(T), "_", i)
                i += 1
            end
            reg.seen[T] = name
            # register before recursing so self-referential types terminate
            reg.schemas[name] = emptyschema()
            reg.schemas[name] = objectschema(reg, T)
        end
        return obj("\$ref" => "#/components/schemas/$name")
    end
    return emptyschema()
end

function objectschema(reg::SchemaRegistry, ::Type{T}) where {T}
    props = JSON.Object{String,Any}()
    required = String[]
    for (fname, ftype) in zip(fieldnames(T), fieldtypes(T))
        props[string(fname)] = schemaof(reg, ftype)
        # Union{Nothing, ...} (and Any) fields are optional; everything else required
        Nothing <: ftype || push!(required, string(fname))
    end
    s = obj(
        "type" => "object",
        "properties" => props,
        "additionalProperties" => false,
    )
    isempty(required) || (s["required"] = required)
    return s
end
