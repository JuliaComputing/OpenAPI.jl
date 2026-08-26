"""
Runtime support for generated OpenAPI clients.

Generated client modules import this module's machinery instead of carrying a
pasted copy: protocol encoding and decoding, parameter styling, content
negotiation, multipart bodies, security schemes, and the HTTP request core.
Each generated module packages its document-specific data — compiled schema
resources, security schemes, and the default server — into a [`Spec`](@ref)
that its `Client` values carry.
"""
module Runtime

import ..SchemaEngine
using JSON, Base64, Dates, UUIDs

"""
Version of the contract between this runtime and generated modules: the names
generated code imports, the shapes of the data it bakes ([`Spec`](@ref)
keywords, operation tables, schema descriptors, dialect literals), and their
semantics. Bump this whenever any of those change so previously generated
modules fail loudly at load time instead of misbehaving; see
[`require_contract`](@ref).
"""
const CONTRACT_VERSION = 2

"""
    Runtime.require_contract(version::Integer, generator::AbstractString)

Called at load time by every generated module to assert that the loaded
runtime still provides the contract the module was generated against;
`generator` records the OpenAPI.jl version that produced the module. Throws
with regeneration guidance on mismatch. This function and
[`CONTRACT_VERSION`](@ref) are permanently stable names: renaming either would
make old generated modules fail with a bare `UndefVarError` instead of this
error.
"""
function require_contract(version::Integer, generator::AbstractString)
    version == CONTRACT_VERSION && return nothing
    runtime = something(pkgversion(@__MODULE__), "unknown")
    return error(
        "this generated module was produced by OpenAPI.jl v",
        generator,
        " against generated-code contract ",
        version,
        ", but the loaded OpenAPI.jl v",
        runtime,
        " provides contract ",
        CONTRACT_VERSION,
        "; regenerate the module with `OpenAPI.client` or `OpenAPI.server`.",
    )
end

"""
Document-specific data a generated module supplies to the shared runtime:
schema resources for validation, security schemes, and server defaults.
Mutable runtime state (the module-wide server override and the compiled
schema-graph cache) lives here so independent generated modules never share
or clobber each other's state.
"""
struct Spec
    security_schemes::Dict{String,NamedTuple}
    resources::Vector{Any}
    roots::Vector{Any}
    dialects::Vector{Any}
    directional_required::Vector{Any}
    default_server::String
    server::Base.RefValue{String}
    graphs::Dict{Symbol,Any}
    graph_lock::ReentrantLock
    # Generated data is required and name-mapped so an omitted keyword or a
    # declaration reorder cannot silently substitute an empty or adjacent
    # Vector{Any} field.
    function Spec(;
        security_schemes::Dict{String,NamedTuple},
        resources::Vector{Any},
        roots::Vector{Any},
        dialects::Vector{Any},
        directional_required::Vector{Any},
        default_server::AbstractString,
    )
        normalized_server = String(default_server)
        values = (;
            security_schemes,
            resources,
            roots,
            dialects,
            directional_required,
            default_server = normalized_server,
            server = Ref(normalized_server),
            graphs = Dict{Symbol,Any}(),
            graph_lock = ReentrantLock(),
        )
        ordered = map(field -> getproperty(values, field), fieldnames(Spec))
        return new(ordered...)
    end
end

struct Absent end
const ABSENT = Absent()
Base.show(io::IO, ::Absent) = print(io, "ABSENT")

struct DecodeError <: Exception
    message::String
end
Base.showerror(io::IO, error::DecodeError) = print(io, error.message)

struct UnsupportedMediaType <: Exception
    media_type::String
    direction::Symbol
end
Base.showerror(io::IO, error::UnsupportedMediaType) = print(
    io,
    "no ",
    error.direction,
    " codec is configured for media type ",
    repr(error.media_type),
)

struct SchemaValidationError <: Exception
    context::String
    issues::Vector{Any}
end
function Base.showerror(io::IO, error::SchemaValidationError)
    print(io, "schema validation failed while ", error.context)
    for issue in error.issues
        print(io, "\n  ", issue.path, ": ", issue.reason)
    end
end

function _schema_graph(spec::Spec, direction::Symbol = :neutral)
    direction in (:neutral, :input, :output) ||
        throw(ArgumentError("schema direction must be :neutral, :input, or :output"))
    isempty(spec.roots) && return nothing
    haskey(spec.graphs, direction) && return spec.graphs[direction]
    return lock(spec.graph_lock) do
        haskey(spec.graphs, direction) && return spec.graphs[direction]
        documents = Dict{String,Any}(
            entry.id => JSON.parse(entry.json; duplicate_keys = :error) for
            entry in spec.resources
        )
        if direction !== :neutral
            for rule in spec.directional_required
                removed = direction === :input ? rule.input : rule.output
                isempty(removed) && continue
                document = get(documents, rule.resource, nothing)
                document === nothing && continue
                schema = SchemaEngine.Resources.resolve(
                    document,
                    SchemaEngine.Resources.JSONPointer(rule.pointer),
                )
                schema isa AbstractDict || continue
                required = get(schema, "required", nothing)
                required isa AbstractVector || continue
                retained = Any[
                    name for name in required if String(name) ∉ removed
                ]
                isempty(retained) ? delete!(schema, "required") :
                (schema["required"] = retained)
            end
        end
        resources = SchemaEngine.Resources.Resource[]
        for entry in spec.resources
            id = SchemaEngine.Resources.ResourceId(entry.id)
            retrieval = SchemaEngine.Resources.ResourceId(entry.retrieval)
            push!(
                resources,
                SchemaEngine.Resources.Resource(
                    id,
                    documents[entry.id];
                    retrieval,
                    media_type = entry.media_type,
                ),
            )
        end
        roots = SchemaEngine.Resources.NodeId[
            SchemaEngine.Resources.NodeId(
                SchemaEngine.Resources.ResourceId(entry.resource),
                SchemaEngine.Resources.JSONPointer(entry.pointer),
            ) for entry in spec.roots
        ]
        root_dialects = Dict(
            root => entry.dialect for (root, entry) in zip(roots, spec.roots)
        )
        dialect_aliases = Dict(
            entry.uri => SchemaEngine.Dialect(;
                name = entry.name,
                uri = entry.uri,
                id_keyword = entry.id_keyword,
                ref_siblings = entry.ref_siblings,
                modern_items = entry.modern_items,
                unevaluated = entry.unevaluated,
                dynamic_refs = entry.dynamic_refs,
                recursive_refs = entry.recursive_refs,
                applicator = entry.applicator,
                validation = entry.validation,
            ) for entry in spec.dialects
        )
        graph = SchemaEngine.CompiledSchemas(
            resources,
            roots;
            dialect = SchemaEngine.DRAFT202012,
            root_dialects,
            dialect_aliases,
        )
        spec.graphs[direction] = graph
        return graph
    end
end

function _schema_at(spec::Spec, descriptor, direction::Symbol = :neutral)
    descriptor === nothing && return nothing
    graph = _schema_graph(spec, direction)
    graph === nothing && throw(ArgumentError(
        "generated schema metadata has a descriptor but no schema roots; regenerate the module",
    ))
    node = SchemaEngine.Resources.NodeId(
        SchemaEngine.Resources.ResourceId(descriptor.resource),
        SchemaEngine.Resources.JSONPointer(descriptor.pointer),
    )
    return SchemaEngine.subschema(graph, node)
end

function _schema_issues(spec::Spec, descriptor, value; direction::Symbol = :neutral)
    schema = _schema_at(spec, descriptor, direction)
    schema === nothing && return Any[]
    return Any[SchemaEngine.validate(schema, value; fail_fast = false)...]
end

function _validate_schema(
    spec::Spec,
    descriptor,
    value,
    context;
    direction::Symbol = :neutral,
)
    issues = _schema_issues(spec, descriptor, value; direction)
    isempty(issues) || throw(SchemaValidationError(String(context), issues))
    return value
end

_schema_valid(spec::Spec, descriptor, value; direction::Symbol = :neutral) =
    isempty(_schema_issues(spec, descriptor, value; direction))

struct Upload
    data::Vector{UInt8}
    filename::Union{Nothing,String}
    content_type::Union{Nothing,String}
    headers::Vector{Pair{String,String}}
end

# Header values for one multipart part and, when needed, its nested parts.
struct MultipartPartHeaders
    values::Any
    parts::Any
end
MultipartPartHeaders(values = NamedTuple(); parts = NamedTuple()) =
    MultipartPartHeaders(values, parts)
function Upload(
    data::AbstractVector{UInt8};
    filename::Union{Nothing,AbstractString} = nothing,
    content_type::Union{Nothing,AbstractString} = nothing,
    headers = Pair{String,String}[],
)
    return Upload(
        Vector{UInt8}(data),
        filename === nothing ? nothing : String(filename),
        content_type === nothing ? nothing : String(content_type),
        Pair{String,String}[String(key) => String(value) for (key, value) in headers],
    )
end

_typename(::Type{T}) where {T} = string(T)
_required(value, key, model) = haskey(value, key) ? value[key] :
    throw(DecodeError("required field $(repr(key)) is missing while decoding $model"))
_object(value, model) = value isa AbstractDict ? value :
    throw(DecodeError("expected an object while decoding $model, got $(typeof(value))"))

_decode(::Type{Any}, value) = value
_decode(::Type{Nothing}, ::Nothing) = nothing
_decode(::Type{Nothing}, value) = throw(DecodeError("expected null, got $(typeof(value))"))
_decode(::Type{String}, value::AbstractString) = String(value)
_decode(::Type{Bool}, value::Bool) = value
_decode(::Type{T}, value::Integer) where {T<:Integer} = try
    value isa Bool && throw(DecodeError("expected an integer, got Bool"))
    convert(T, value)
catch
    throw(DecodeError("integer $value does not fit $T"))
end
function _decode(::Type{T}, value::Real) where {T<:AbstractFloat}
    value isa Bool && throw(DecodeError("expected a number, got Bool"))
    return convert(T, value)
end
function _decode(::Type{Dates.Date}, value::AbstractString)
    try
        return Dates.Date(value)
    catch error
        throw(DecodeError("invalid RFC 3339 full-date: $(sprint(showerror, error))"))
    end
end
function _decode(::Type{Dates.Time}, value::AbstractString)
    try
        return Dates.Time(value)
    catch error
        throw(DecodeError("invalid time: $(sprint(showerror, error))"))
    end
end
function _decode(::Type{Dates.DateTime}, value::AbstractString)
    # RFC 3339 requires the offset, but zone-less ISO 8601 date-times are
    # widespread in deployed APIs (most JSON serializers print naive
    # timestamps). Accept input liberally: a missing offset means UTC, the
    # same convention _encode uses when it stamps naive DateTimes with `Z`.
    matched = match(
        r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})?$",
        value,
    )
    matched === nothing && throw(DecodeError("invalid RFC 3339 date-time $(repr(value))"))
    try
        output = Dates.DateTime(matched.captures[1])
        fraction = matched.captures[2]
        if fraction !== nothing
            milliseconds = parse(Int, rpad(first(fraction, min(3, length(fraction))), 3, '0'))
            output += Dates.Millisecond(milliseconds)
        end
        zone = matched.captures[3]
        if zone !== nothing && zone != "Z"
            sign = startswith(zone, '+') ? 1 : -1
            hours = parse(Int, zone[2:3])
            minutes = parse(Int, zone[5:6])
            output -= Dates.Minute(sign * (60 * hours + minutes))
        end
        return output
    catch error
        error isa DecodeError && rethrow()
        throw(DecodeError("invalid RFC 3339 date-time: $(sprint(showerror, error))"))
    end
end
function _decode(::Type{UUIDs.UUID}, value::AbstractString)
    try
        return UUIDs.UUID(value)
    catch error
        throw(DecodeError("invalid UUID: $(sprint(showerror, error))"))
    end
end
function _decode(::Type{Vector{UInt8}}, value::AbstractString)
    try
        return Base64.base64decode(value)
    catch error
        throw(DecodeError("invalid base64 data: $(sprint(showerror, error))"))
    end
end
_decode(::Type{Vector{UInt8}}, value::AbstractVector{UInt8}) = copy(value)

_decode(::Type{T}, value::AbstractVector) where {T<:AbstractVector} =
    _decode(T, value, true)
function _decode(::Type{T}, value::AbstractVector, validate::Bool) where {T<:AbstractVector}
    element = eltype(T)
    return T([_decode(element, item, validate) for item in value])
end
_decode(::Type{T}, value::AbstractDict) where {T<:AbstractDict} =
    _decode(T, value, true)
function _decode(::Type{T}, value::AbstractDict, validate::Bool) where {T<:AbstractDict}
    keytype(T) <: AbstractString ||
        throw(DecodeError("only string-key dictionaries are supported, got $T"))
    output = T()
    for (key, item) in value
        output[convert(keytype(T), key)] = _decode(valtype(T), item, validate)
    end
    return output
end
_decode(::Type{T}, value::AbstractVector) where {T<:Tuple} =
    _decode(T, value, true)
function _decode(::Type{T}, value::AbstractVector, validate::Bool) where {T<:Tuple}
    length(value) == fieldcount(T) ||
        throw(DecodeError("expected $(fieldcount(T)) tuple items, got $(length(value))"))
    return T((
        _decode(fieldtype(T, index), value[index], validate) for
        index in 1:fieldcount(T)
    )...)
end

function _direct_union_match(::Type{T}, value) where {T}
    T === Nothing && return value === nothing
    T === Bool && return value isa Bool
    T <: Integer && return value isa Integer && !(value isa Bool)
    T <: AbstractFloat && return value isa AbstractFloat
    T <: AbstractString && return value isa AbstractString
    T <: AbstractVector && return value isa AbstractVector
    T <: AbstractDict && return value isa AbstractDict
    return value isa T
end

function _decode_union(
    ::Type{T},
    value;
    oneof::Bool = false,
    validate::Bool = true,
) where {T}
    variants = Base.uniontypes(T)
    if value === nothing && Nothing in variants
        return nothing
    end
    if !oneof
        preferred = Any[
            variant for variant in variants
            if variant ∉ (Absent, Nothing) && _direct_union_match(variant, value)
        ]
        append!(preferred, Any[variant for variant in variants if variant ∉ preferred])
        variants = preferred
    end
    successes = Any[]
    failures = String[]
    for variant in variants
        variant in (Absent, Nothing) && continue
        try
            decoded = _decode(variant, value, validate)
            oneof || return decoded
            push!(successes, decoded)
        catch error
            error isa DecodeError || rethrow()
            push!(failures, error.message)
        end
    end
    length(successes) == 1 && return only(successes)
    isempty(successes) && throw(
        DecodeError("value does not match any variant of $T: " * join(failures, "; ")),
    )
    throw(DecodeError("value matches more than one variant of $T"))
end

function _decode(::Type{T}, value) where {T}
    T isa Union && return _decode_union(T, value)
    value isa T && return value
    try
        return convert(T, value)
    catch
        throw(DecodeError("cannot decode $(typeof(value)) as $T"))
    end
end

function _decode(::Type{T}, value, validate::Bool) where {T}
    T isa Union && return _decode_union(T, value; validate)
    return _decode(T, value)
end

_encode(::Absent) = throw(ArgumentError("ABSENT is only valid as an object field"))
_encode(::Nothing) = nothing
_encode(value::Union{Bool,Number,AbstractString}) = value
_encode(value::Union{Dates.Date,Dates.Time,UUIDs.UUID}) = string(value)
_encode(value::Dates.DateTime) = Dates.format(value, dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"
_encode(value::AbstractVector{UInt8}) = Base64.base64encode(value)
_encode(value::Upload) = Base64.base64encode(value.data)
_encode(value::AbstractVector) = Any[_encode(item) for item in value]
_encode(value::Tuple) = Any[_encode(item) for item in value]
function _encode(value::AbstractDict)
    output = JSON.Object{String,Any}()
    for (key, item) in value
        output[String(key)] = _encode(item)
    end
    return output
end
function _encode(value::NamedTuple)
    output = JSON.Object{String,Any}()
    for (key, item) in pairs(value)
        output[String(key)] = _encode(item)
    end
    return output
end
_encode(value) = value

function _safe_header(name, value)
    header = String(name)
    content = String(value)
    occursin(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$", header) ||
        throw(ArgumentError("invalid HTTP header name $(repr(header))"))
    (occursin('\r', content) || occursin('\n', content)) &&
        throw(ArgumentError("HTTP header values must not contain CR or LF"))
    return header => content
end

function _set_header!(headers, name, value)
    pair = _safe_header(name, value)
    lowered = lowercase(pair.first)
    filter!(entry -> lowercase(entry.first) != lowered, headers)
    push!(headers, pair)
    return headers
end

function _media_segments(value)
    output = String[]
    io = IOBuffer()
    quoted = false
    escaped = false
    for char in String(value)
        if escaped
            write(io, char)
            escaped = false
        elseif quoted && char == '\\'
            write(io, char)
            escaped = true
        elseif char == '"'
            write(io, char)
            quoted = !quoted
        elseif char == ';' && !quoted
            push!(output, String(take!(io)))
        else
            write(io, char)
        end
    end
    push!(output, String(take!(io)))
    return output
end

function _media_parameter_value(value)
    text = strip(String(value))
    startswith(text, '"') && endswith(text, '"') && ncodeunits(text) >= 2 ||
        return text
    ncodeunits(text) == 2 && return ""
    io = IOBuffer()
    escaped = false
    for char in SubString(text, nextind(text, firstindex(text)), prevind(text, lastindex(text)))
        if escaped
            write(io, char)
            escaped = false
        elseif char == '\\'
            escaped = true
        else
            write(io, char)
        end
    end
    escaped && write(io, '\\')
    return String(take!(io))
end

function _media_type(value)
    segments = _media_segments(value)
    base = lowercase(strip(first(segments)))
    parameters = Dict{String,String}()
    for segment in Iterators.drop(segments, 1)
        pair = split(segment, '='; limit = 2)
        length(pair) == 2 || continue
        name = lowercase(strip(pair[1]))
        isempty(name) && continue
        parameter = _media_parameter_value(pair[2])
        parameters[name] = name == "charset" ? lowercase(parameter) : parameter
    end
    return base, parameters
end

function _media_match_score(received::String, documented::String)
    received_base = first(_media_type(received))
    documented_base = first(_media_type(documented))
    received_base == documented_base && return 4
    documented_base == "*/*" && return 1
    parts = split(documented_base, '/'; limit = 2)
    received_parts = split(received_base, '/'; limit = 2)
    length(parts) == 2 && length(received_parts) == 2 || return 0
    parts[1] == received_parts[1] || parts[1] == "*" || return 0
    parts[2] == "*" && return parts[1] == "*" ? 1 : 2
    startswith(parts[2], "*+") &&
        endswith(received_parts[2], parts[2][2:end]) && return 3
    return 0
end

function _media_selection_score(received::String, documented::String)
    received_base, received_parameters = _media_type(received)
    documented_base, documented_parameters = _media_type(documented)
    base_score = _media_match_score(received_base, documented_base)
    base_score > 0 || return (0, 0, 0)
    all(documented_parameters) do (name, value)
        return get(received_parameters, name, nothing) == value
    end || return (0, 0, 0)
    exact = length(received_parameters) == length(documented_parameters)
    return (base_score, length(documented_parameters), exact ? 1 : 0)
end

_media_match(received::String, documented::String) =
    first(_media_selection_score(received, documented)) > 0

_base_media_type(value) = lowercase(strip(first(split(String(value), ';'; limit = 2))))

function _select_media(media, received)
    isempty(media) && return nothing
    selected = nothing
    score = (0, 0, 0)
    for entry in media
        candidate = _media_selection_score(String(received), String(entry[1]))
        if candidate > score
            selected = entry
            score = candidate
        end
    end
    return selected
end

function _select_media_codec(codecs, received)
    selected = nothing
    score = (0, 0, 0)
    for (documented, codec) in codecs
        candidate = _media_selection_score(String(received), documented)
        if candidate > score
            selected = codec
            score = candidate
        end
    end
    return selected
end

function _store_media_codec!(codecs, media_type, codec)
    key = strip(String(media_type))
    parsed = _media_type(key)
    for existing in collect(keys(codecs))
        _media_type(existing) == parsed && delete!(codecs, existing)
    end
    codecs[key] = codec
    return codecs
end

function _select_response(responses, status)
    exact = string(status)
    range = string(div(status, 100), "XX")
    default = nothing
    for response in responses
        selector = uppercase(response.selector)
        selector == exact && return response
        selector == range && (default = response)
        selector == "DEFAULT" && default === nothing && (default = response)
    end
    return default
end

function _header_values(headers, name)
    lowered = lowercase(String(name))
    return String[
        value for (key, value) in headers if lowercase(String(key)) == lowered
    ]
end

function _header_atom(value)
    text = String(value)
    lowered = lowercase(text)
    lowered == "true" && return true
    lowered == "false" && return false
    lowered == "null" && return nothing
    integer = tryparse(Int64, text)
    integer === nothing || return integer
    number = tryparse(Float64, text)
    number === nothing || return number
    return text
end

function _header_scalar(type, value)
    text = String(value)
    type === String && return text
    type === Bool && return lowercase(text) == "true" ? true :
                         lowercase(text) == "false" ? false :
                         throw(DecodeError("invalid boolean value $(repr(text))"))
    type <: Integer && return try
        parse(type, text)
    catch error
        throw(DecodeError("invalid integer value: $(sprint(showerror, error))"))
    end
    type <: AbstractFloat && return try
        parse(type, text)
    catch error
        throw(DecodeError("invalid numeric value: $(sprint(showerror, error))"))
    end
    return _decode(type, text)
end

function _header_type_variant(type, shape)
    variants = type isa Union ? Base.uniontypes(type) : (type,)
    for variant in variants
        variant in (Nothing, Absent) && continue
        shape === :array && variant <: AbstractVector && return variant
        shape === :object &&
            (variant <: AbstractDict || isstructtype(variant)) && return variant
        shape === :scalar && return variant
    end
    return type
end

function _decode_schema_header(
    spec::Spec,
    type,
    values,
    shape,
    explode,
    schema;
    set_cookie::Bool = false,
    direction::Symbol = :output,
    context = "decoding a response header",
    validate::Bool = true,
)
    selected = _header_type_variant(type, shape)
    raw = if shape === :array
        items = if set_cookie
            String[String(value) for value in values]
        else
            output = String[]
            for value in values
                append!(output, split(value, ','))
            end
            output
        end
        element = selected <: AbstractVector ? eltype(selected) : String
        Any[_header_scalar(element, item) for item in items]
    elseif shape === :object
        object = JSON.Object{String,Any}()
        if set_cookie && explode
            for value in values
                pair = split(value, '='; limit = 2)
                length(pair) == 2 || throw(
                    DecodeError("invalid Set-Cookie response header"),
                )
                object[pair[1]] = pair[2]
            end
        elseif explode
            tokens = split(join(values, ','), ',')
            for token in tokens
                pair = split(token, '='; limit = 2)
                length(pair) == 2 || throw(
                    DecodeError("invalid exploded object response header"),
                )
                object[pair[1]] = _header_atom(pair[2])
            end
        else
            tokens = split(join(values, ','), ',')
            iseven(length(tokens)) ||
                throw(DecodeError("invalid object response header"))
            for index in 1:2:length(tokens)
                object[tokens[index]] = _header_atom(tokens[index + 1])
            end
        end
        object
    else
        _header_scalar(selected, join(values, set_cookie ? '\n' : ','))
    end
    validate && _validate_schema(
        spec,
        schema,
        _encode(raw),
        context;
        direction,
    )
    return _decode(type, raw, validate)
end

_is_json_media(media) = media == "application/json" || endswith(media, "+json")
_is_sequential_json_media(media) = media in (
    "application/jsonl",
    "application/x-ndjson",
    "application/json-seq",
    "application/geo+json-seq",
) || endswith(media, "+json-seq")

function _parse_json(text, context)
    source = text isa AbstractString ? String(text) : String(copy(text))
    isvalid(source) || throw(DecodeError("invalid UTF-8 while $context"))
    try
        return JSON.parse(source; duplicate_keys = :error)
    catch error
        throw(DecodeError("invalid JSON while $context: $(sprint(showerror, error))"))
    end
end

function _decode_sequential_json(body, media)
    records = Any[]
    if media == "application/json-seq" || endswith(media, "+json-seq")
        for chunk in split(String(body), Char(0x1e))
            text = strip(chunk)
            isempty(text) || push!(records, _parse_json(text, "decoding a JSON sequence"))
        end
    else
        for line in eachline(IOBuffer(body))
            text = strip(line)
            isempty(text) || push!(records, _parse_json(text, "decoding JSON lines"))
        end
    end
    return records
end

function _encode_sequential_json(value, media)
    encoded = _encode(value)
    encoded isa AbstractVector || encoded isa Tuple || throw(
        ArgumentError("sequential JSON request bodies must be arrays or tuples"),
    )
    if media == "application/json-seq" || endswith(media, "+json-seq")
        return join((string(Char(0x1e), JSON.json(item), '\n') for item in encoded))
    end
    return join((JSON.json(item) * "\n" for item in encoded))
end
struct ApiError <: Exception
    operation_id::String
    status::Int
    headers::Vector{Pair{String,String}}
    decoded_headers::Dict{String,Any}
    body::Vector{UInt8}
    decoded::Any
    decode_error::Any
end
function Base.showerror(io::IO, error::ApiError)
    print(io, "ApiError(", error.status, ") in ", error.operation_id)
    if error.decode_error !== nothing
        print(io, " (response decoding failed: ")
        showerror(io, error.decode_error)
        print(io, ')')
    end
    isempty(error.body) && return
    text = isvalid(String, error.body) ? String(copy(error.body)) : nothing
    if text === nothing
        preview = bytes2hex(error.body[1:min(length(error.body), 32)])
        print(io, ": ", length(error.body), " binary bytes (", preview)
        length(error.body) > 32 && print(io, "…")
        print(io, ')')
    else
        preview = first(text, min(length(text), 512))
        print(io, ": ", preview)
        length(text) > 512 && print(io, "…")
    end
end

struct ApiResponse{T}
    status::Int
    headers::Vector{Pair{String,String}}
    decoded_headers::Dict{String,Any}
    body::T
end

struct UnexpectedBody <: Exception
    operation_id::String
    status::Int
    bytes::Int
end
Base.showerror(io::IO, error::UnexpectedBody) = print(
    io,
    "operation ",
    error.operation_id,
    " received an undocumented ",
    error.bytes,
    "-byte response body for status ",
    error.status,
)

struct UnexpectedContentType <: Exception
    operation_id::String
    status::Int
    received::String
    expected::Tuple
end
function Base.showerror(io::IO, error::UnexpectedContentType)
    print(
        io,
        "unexpected Content-Type ",
        repr(error.received),
        " for ",
        error.operation_id,
        " response ",
        error.status,
        "; expected ",
        join(error.expected, ", "),
    )
end

abstract type AbstractCredential end
struct ApiKeyCredential <: AbstractCredential
    value::String
    authorizations::Set{String}
end
ApiKeyCredential(value::AbstractString; roles = String[]) =
    ApiKeyCredential(String(value), Set(String.(roles)))
struct BasicCredential <: AbstractCredential
    username::String
    password::String
    authorizations::Set{String}
end
BasicCredential(username::AbstractString, password::AbstractString; roles = String[]) =
    BasicCredential(String(username), String(password), Set(String.(roles)))
struct BearerCredential <: AbstractCredential
    token::String
    authorizations::Set{String}
end
function BearerCredential(token::AbstractString; scopes = String[], roles = String[])
    return BearerCredential(
        String(token),
        union(Set(String.(scopes)), Set(String.(roles))),
    )
end
struct HttpCredential <: AbstractCredential
    value::String
    authorizations::Set{String}
end
HttpCredential(value::AbstractString; roles = String[]) =
    HttpCredential(String(value), Set(String.(roles)))
struct MutualTLSCredential <: AbstractCredential
    request_options::NamedTuple
    authorizations::Set{String}
end
MutualTLSCredential(request_options::NamedTuple; roles = String[]) =
    MutualTLSCredential(request_options, Set(String.(roles)))

mutable struct Client
    spec::Spec
    is_default::Bool
    server::Union{Nothing,String}
    server_index::Int
    server_name::Union{Nothing,String}
    server_variables::Dict{String,String}
    credentials::Dict{String,AbstractCredential}
    headers::Vector{Pair{String,String}}
    request_options::NamedTuple
    require_credentials::Bool
    media_encoders::Dict{String,Function}
    media_decoders::Dict{String,Function}
    validate_requests::Bool
    validate_responses::Bool
end

function _normalize_media_codecs(codecs::AbstractDict)
    normalized = Dict{String,Function}()
    for (name, codec) in codecs
        _store_media_codec!(normalized, name, codec)
    end
    return normalized
end

function Client(
    spec::Spec,
    server::Union{Nothing,AbstractString} = nothing;
    _default::Bool = false,
    server_index::Integer = 1,
    server_name::Union{Nothing,AbstractString} = nothing,
    server_variables::AbstractDict = Dict{String,String}(),
    credentials::AbstractDict = Dict{String,AbstractCredential}(),
    headers = Pair{String,String}[],
    request_options::NamedTuple = NamedTuple(),
    require_credentials::Bool = true,
    media_encoders::AbstractDict = Dict{String,Function}(),
    media_decoders::AbstractDict = Dict{String,Function}(),
    validate_requests::Bool = true,
    validate_responses::Bool = true,
)
    server_index > 0 || throw(ArgumentError("server_index must be positive"))
    normalized_credentials = credentials isa Dict{String,AbstractCredential} ?
                             copy(credentials) :
                             Dict{String,AbstractCredential}(
        String(name) => credential for (name, credential) in credentials
    )
    normalized_headers = headers isa Vector{Pair{String,String}} ? copy(headers) :
                         Pair{String,String}[
        String(name) => String(value) for (name, value) in headers
    ]
    return Client(
        spec,
        _default,
        server === nothing ? nothing : String(rstrip(server, '/')),
        Int(server_index),
        server_name === nothing ? nothing : String(server_name),
        server_variables isa Dict{String,String} ? copy(server_variables) :
        Dict{String,String}(
            String(name) => String(value) for (name, value) in server_variables
        ),
        normalized_credentials,
        normalized_headers,
        request_options,
        require_credentials,
        _normalize_media_codecs(media_encoders),
        _normalize_media_codecs(media_decoders),
        validate_requests,
        validate_responses,
    )
end

function credential!(client::Client, name::AbstractString, credential::AbstractCredential)
    client.credentials[String(name)] = credential
    return client
end

function clearcredential!(client::Client, name::AbstractString)
    delete!(client.credentials, String(name))
    return client
end

function server!(client::Client, server::Union{Nothing,AbstractString})
    client.server = server === nothing ? nothing : String(rstrip(server, '/'))
    client.is_default &&
        (client.spec.server[] = something(client.server, client.spec.default_server))
    return client
end

function server_index!(client::Client, index::Integer)
    index > 0 || throw(ArgumentError("server index must be positive"))
    client.server_index = Int(index)
    client.server_name = nothing
    return client
end

function server_name!(client::Client, name::Union{Nothing,AbstractString})
    client.server_name = name === nothing ? nothing : String(name)
    return client
end

function server_variable!(client::Client, name::AbstractString, value::AbstractString)
    client.server_variables[String(name)] = String(value)
    return client
end

function codec!(
    client::Client,
    media_type::AbstractString;
    encode::Union{Nothing,Function} = nothing,
    decode::Union{Nothing,Function} = nothing,
)
    encode === nothing ||
        _store_media_codec!(client.media_encoders, media_type, encode)
    decode === nothing ||
        _store_media_codec!(client.media_decoders, media_type, decode)
    return client
end

function authorization!(client::Client, token::Union{Nothing,AbstractString})
    names = String[
        name for (name, scheme) in client.spec.security_schemes
        if scheme.type in (:http_bearer, :oauth2, :openidconnect)
    ]
    isempty(names) && throw(ArgumentError("the OpenAPI document has no bearer-compatible security scheme"))
    for name in names
        if token === nothing
            delete!(client.credentials, name)
        else
            client.credentials[name] = BearerCredential(String(token))
        end
    end
    return client
end

_scalar(::Nothing) = ""
_scalar(value::Bool) = value ? "true" : "false"
_scalar(value::Dates.DateTime) = _encode(value)
_scalar(value::Union{Dates.Date,Dates.Time,UUIDs.UUID}) = string(value)
_scalar(value::AbstractVector{UInt8}) = Base64.base64encode(value)
_scalar(value) = string(value)

function _pairs(value)
    lowered = _encode(value)
    lowered isa AbstractDict || throw(ArgumentError("parameter style requires an object value"))
    return Pair{String,Any}[String(key) => item for (key, item) in lowered]
end

function _join_array(value, delimiter)
    value isa AbstractVector || value isa Tuple ||
        throw(ArgumentError("parameter style requires an array value"))
    return join((_scalar(item) for item in value), delimiter)
end

function _join_object(value, pair_delimiter, key_delimiter)
    return join(
        (string(_scalar(key), key_delimiter, _scalar(item)) for (key, item) in _pairs(value)),
        pair_delimiter,
    )
end

_path_scalar(value) = _escape(_scalar(value))

function _path_array(value, delimiter)
    value isa AbstractVector || value isa Tuple ||
        throw(ArgumentError("parameter style requires an array value"))
    return join((_path_scalar(item) for item in value), delimiter)
end

function _path_object(value, pair_delimiter, key_delimiter)
    return join(
        (
            string(
                _path_scalar(key),
                key_delimiter,
                _path_scalar(item),
            ) for (key, item) in _pairs(value)
        ),
        pair_delimiter,
    )
end

function _path_parameter(name, value, style::Symbol, explode::Bool)
    encoded = _encode(value)
    if encoded === nothing
        style === :matrix && return ";" * _path_scalar(name)
        style === :label && return "."
        style === :simple && return ""
    end
    if style === :simple
        encoded isa AbstractDict && return explode ?
            _path_object(encoded, ",", "=") : _path_object(encoded, ",", ",")
        encoded isa AbstractVector && return _path_array(encoded, ",")
        return _path_scalar(encoded)
    elseif style === :label
        encoded isa AbstractDict && return "." * (explode ?
            _path_object(encoded, ".", "=") : _path_object(encoded, ",", ","))
        encoded isa AbstractVector && return "." * _path_array(encoded, explode ? "." : ",")
        return "." * _path_scalar(encoded)
    elseif style === :matrix
        encoded_name = _path_scalar(name)
        if encoded isa AbstractDict
            return explode ?
                join((";" * _path_scalar(key) * "=" * _path_scalar(item) for (key, item) in _pairs(encoded))) :
                ";" * encoded_name * "=" * _path_object(encoded, ",", ",")
        elseif encoded isa AbstractVector
            return explode ?
                join((";" * encoded_name * "=" * _path_scalar(item) for item in encoded)) :
                ";" * encoded_name * "=" * _path_array(encoded, ",")
        end
        return ";" * encoded_name * "=" * _path_scalar(encoded)
    end
    throw(ArgumentError("unsupported path parameter style $style"))
end

function _form_component(value, allow_reserved)
    encoded = _escape(_scalar(value); allow_reserved)
    return replace(encoded, "," => "%2C")
end

function _query_parameter(
    name,
    value,
    style::Symbol,
    explode::Bool,
    allow_reserved::Bool,
)
    encoded = _encode(value)
    if style === :deepObject
        if encoded isa AbstractDict
            any(
                item -> item isa AbstractDict || item isa AbstractVector || item isa Tuple,
                values(encoded),
            ) && throw(ArgumentError("deepObject does not define nested object or array values"))
            return Tuple{String,String,Bool}[
                (string(name, '[', key, ']'), _scalar(item), false) for
                (key, item) in _pairs(encoded)
            ]
        elseif encoded isa AbstractVector || encoded isa Tuple
            return Tuple{String,String,Bool}[
                (string(name, "[]"), _scalar(item), false) for item in encoded
            ]
        end
        return [(name, _scalar(encoded), false)]
    elseif style in (:spaceDelimited, :pipeDelimited)
        explode && throw(ArgumentError("$style with explode=true is undefined"))
        delimiter = style === :spaceDelimited ? " " : "|"
        if encoded isa AbstractDict
            return [(name, _join_object(encoded, delimiter, delimiter), false)]
        end
        return [(name, _join_array(encoded, delimiter), false)]
    elseif style === :form
        if encoded isa AbstractDict
            return explode ?
                Tuple{String,String,Bool}[
                    (_scalar(key), _scalar(item), false) for
                    (key, item) in _pairs(encoded)
                ] :
                [
                    (
                        name,
                        join(
                            (
                                _form_component(key, allow_reserved) * "," *
                                _form_component(item, allow_reserved) for
                                (key, item) in _pairs(encoded)
                            ),
                            ",",
                        ),
                        true,
                    ),
                ]
        elseif encoded isa AbstractVector
            return explode ?
                Tuple{String,String,Bool}[
                    (name, _scalar(item), false) for item in encoded
                ] :
                [
                    (
                        name,
                        join(
                            (_form_component(item, allow_reserved) for item in encoded),
                            ",",
                        ),
                        true,
                    ),
                ]
        end
        return [(name, _scalar(encoded), false)]
    end
    throw(ArgumentError("unsupported query parameter style $style"))
end

function _header_parameter(value, explode::Bool)
    encoded = _encode(value)
    encoded isa AbstractDict && return explode ?
        _join_object(encoded, ",", "=") : _join_object(encoded, ",", ",")
    encoded isa AbstractVector && return _join_array(encoded, ",")
    return _scalar(encoded)
end

function _cookie_parameter(
    name,
    value,
    style::Symbol,
    explode::Bool,
    allow_reserved::Bool,
)
    style in (:form, :cookie) ||
        throw(ArgumentError("unsupported cookie parameter style $style"))
    encoded = _encode(value)
    if style === :form
        pairs = _query_parameter(name, value, :form, explode, allow_reserved)
        fragment = join(
            (
                _escape(key) * "=" *
                (preencoded ? item : _escape(item; allow_reserved)) for
                (key, item, preencoded) in pairs
            ),
            '&',
        )
        return [(fragment, "", true, true)]
    elseif encoded isa AbstractDict
        return explode ?
            Tuple{String,String,Bool,Bool}[
                (_scalar(key), _scalar(item), true, false) for
                (key, item) in _pairs(encoded)
            ] :
            [(name, _join_object(encoded, ",", ","), true, false)]
    elseif encoded isa AbstractVector
        return explode ?
            Tuple{String,String,Bool,Bool}[
                (name, _scalar(item), true, false) for item in encoded
            ] :
            [(name, _join_array(encoded, ","), true, false)]
    end
    return [(name, _scalar(encoded), true, false)]
end

# RFC 3986 percent-encoding of everything outside the unreserved set. Local
# so the parameter machinery works without HTTP.jl loaded.
function _escapeuri(text)
    io = IOBuffer()
    for byte in codeunits(String(text))
        char = Char(byte)
        if char in 'A':'Z' || char in 'a':'z' || char in '0':'9' || char in "-_.~"
            write(io, char)
        else
            print(io, '%', uppercase(string(byte; base = 16, pad = 2)))
        end
    end
    return String(take!(io))
end

# The HTTP transport core lives in OpenAPIHTTPExt; generated clients say
# `using HTTP`, which loads the extension and adds methods to these stubs.
function _request end
function _stream_request end
function _pump_stream! end
function _abort_stream_on_close! end

_is_hex_digit(char) = isdigit(char) || 'a' <= lowercase(char) <= 'f'

function _escape(value; allow_reserved::Bool = false)
    text = String(value)
    allow_reserved || return _escapeuri(text)
    io = IOBuffer()
    index = firstindex(text)
    while index <= lastindex(text)
        char = text[index]
        if char == '%'
            second = nextind(text, index)
            third = second <= lastindex(text) ? nextind(text, second) : second
            if third <= lastindex(text) &&
               _is_hex_digit(text[second]) &&
               _is_hex_digit(text[third])
                write(io, char, text[second], text[third])
                index = nextind(text, third)
                continue
            end
        end
        if char in ":/?#[]@!\$&'()*+,;="
            write(io, char)
        else
            write(io, _escapeuri(string(char)))
        end
        index = nextind(text, index)
    end
    return String(take!(io))
end

function _parameter_content_value(client, entry, value)
    encoded = _encoded_media_value(client, value, entry[1])
    encoded isa Upload && (encoded = encoded.data)
    if encoded isa AbstractVector{UInt8}
        isvalid(String, encoded) && return String(copy(encoded)), false
        return join(
            ('%' * uppercase(string(byte; base = 16, pad = 2)) for byte in encoded),
        ), true
    end
    return String(encoded), false
end

function _append_parameter!(client, path, query, headers, cookies, descriptor, value)
    location = descriptor.location
    style = descriptor.style
    explode = descriptor.explode
    if location === :querystring
        throw(ArgumentError("OAS 3.2 querystring parameter generation is not implemented"))
    elseif !isempty(descriptor.content)
        serialized, preencoded =
            _parameter_content_value(client, first(descriptor.content), value)
        if location === :path
            path = replace(
                path,
                "{" * descriptor.name * "}" =>
                    (preencoded ? serialized : _escape(serialized)),
            )
        elseif location === :query
            push!(
                query,
                (
                    descriptor.name,
                    serialized,
                    descriptor.allow_reserved,
                    preencoded,
                ),
            )
        elseif location === :header
            _set_header!(headers, descriptor.name, serialized)
        elseif location === :cookie
            push!(cookies, (descriptor.name, serialized, preencoded, false))
        else
            throw(ArgumentError("unsupported parameter location $location"))
        end
    elseif location === :path
        serialized = _path_parameter(descriptor.name, value, style, explode)
        path = replace(path, "{" * descriptor.name * "}" => serialized)
    elseif location === :query
        for (name, item, preencoded) in _query_parameter(
            descriptor.name,
            value,
            style,
            explode,
            descriptor.allow_reserved,
        )
            push!(query, (name, item, descriptor.allow_reserved, preencoded))
        end
    elseif location === :header
        _set_header!(headers, descriptor.name, _header_parameter(value, explode))
    elseif location === :cookie
        append!(
            cookies,
            _cookie_parameter(
                descriptor.name,
                value,
                style,
                explode,
                descriptor.allow_reserved,
            ),
        )
    else
        throw(ArgumentError("unsupported parameter location $location"))
    end
    return path
end

_authorizations(credential::AbstractCredential) = credential.authorizations

function _credential_satisfies(scheme, credential, required)
    valid_type = if scheme.type === :apikey
        credential isa ApiKeyCredential
    elseif scheme.type === :http_basic
        credential isa BasicCredential
    elseif scheme.type in (:http_bearer, :oauth2, :openidconnect)
        credential isa BearerCredential
    elseif scheme.type === :mutualtls
        credential isa MutualTLSCredential
    elseif scheme.type === :http
        credential isa HttpCredential
    else
        false
    end
    valid_type || return false
    return all(item -> item in _authorizations(credential), required)
end

function _security!(client, requirements, query, headers, cookies, base_options)
    isempty(requirements) && return base_options
    for requirement in requirements
        isempty(requirement) && return base_options
        all(requirement) do entry
            credential = get(client.credentials, entry[1], nothing)
            credential === nothing && return false
            scheme = get(client.spec.security_schemes, entry[1], nothing)
            return scheme !== nothing &&
                   _credential_satisfies(scheme, credential, entry[2])
        end || continue
        options = base_options
        for (name, _) in requirement
            scheme = client.spec.security_schemes[name]
            credential = client.credentials[name]
            if scheme.type === :apikey
                credential isa ApiKeyCredential ||
                    throw(ArgumentError("security scheme $name requires ApiKeyCredential"))
                if scheme.location === :header
                    _set_header!(headers, scheme.name, credential.value)
                elseif scheme.location === :query
                    push!(query, (scheme.name, credential.value, false, false))
                elseif scheme.location === :cookie
                    push!(cookies, (scheme.name, credential.value, false, false))
                else
                    throw(ArgumentError(string(
                        "security scheme ",
                        name,
                        " has unsupported API key location ",
                        repr(scheme.location),
                    )))
                end
            elseif scheme.type === :http_basic
                credential isa BasicCredential ||
                    throw(ArgumentError("security scheme $name requires BasicCredential"))
                token = Base64.base64encode(credential.username * ":" * credential.password)
                _set_header!(headers, "Authorization", "Basic " * token)
            elseif scheme.type in (:http_bearer, :oauth2, :openidconnect)
                credential isa BearerCredential ||
                    throw(ArgumentError("security scheme $name requires BearerCredential"))
                _set_header!(headers, "Authorization", "Bearer " * credential.token)
            elseif scheme.type === :mutualtls
                credential isa MutualTLSCredential ||
                    throw(ArgumentError("security scheme $name requires MutualTLSCredential"))
                options = merge(options, credential.request_options)
            elseif scheme.type === :http
                credential isa HttpCredential ||
                    throw(ArgumentError("security scheme $name requires HttpCredential"))
                _set_header!(
                    headers,
                    "Authorization",
                    scheme.scheme * " " * credential.value,
                )
            else
                throw(ArgumentError("security scheme type $(scheme.type) is not supported"))
            end
        end
        return options
    end
    names = join((join(first.(requirement), " + ") for requirement in requirements), " or ")
    client.require_credentials && throw(
        ArgumentError("no configured credentials satisfy operation security: " * names),
    )
    return base_options
end

function _decode_response_headers(client, descriptor, headers)
    output = Dict{String,Any}()
    descriptor === nothing && return output
    for header in descriptor.headers
        values = _header_values(headers, header.name)
        if isempty(values)
            header.required && throw(
                DecodeError("required response header $(repr(header.name)) is missing"),
            )
            continue
        end
        decoded = if isempty(header.content)
            _decode_schema_header(client.spec, 
                header.type,
                values,
                header.shape,
                header.explode,
                header.schema,
                set_cookie = lowercase(header.name) == "set-cookie",
                validate = client.validate_responses,
            )
        else
            entry = first(header.content)
            separator = lowercase(header.name) == "set-cookie" ? '\n' : ','
            _decode_body(
                client,
                header.type,
                entry[1],
                Vector{UInt8}(codeunits(join(values, separator))),
                entry[3],
            )
        end
        output[header.name] = decoded
    end
    return output
end

function _decode_body(client::Client, type, content_type, body, schema)
    media = _base_media_type(content_type)
    decoder = _select_media_codec(client.media_decoders, content_type)
    if decoder !== nothing
        value = decoder(copy(body), String(content_type))
        lowered = _encode(value)
        client.validate_responses &&
            _validate_schema(client.spec, 
                schema,
                lowered,
                "decoding a custom-media response";
                direction = :output,
            )
        return _decode(type, lowered, client.validate_responses)
    elseif _is_json_media(media)
        if isempty(body)
            client.validate_responses &&
                _validate_schema(client.spec, 
                    schema,
                    nothing,
                    "decoding an empty JSON response";
                    direction = :output,
                )
            return _decode(type, nothing, client.validate_responses)
        end
        value = _parse_json(body, "decoding a response")
        client.validate_responses &&
            _validate_schema(client.spec, 
                schema,
                value,
                "decoding a JSON response";
                direction = :output,
            )
        return _decode(type, value, client.validate_responses)
    elseif _is_sequential_json_media(media)
        value = _decode_sequential_json(body, media)
        client.validate_responses &&
            _validate_schema(client.spec, 
                schema,
                value,
                "decoding a sequential JSON response";
                direction = :output,
            )
        return _decode(type, value, client.validate_responses)
    elseif startswith(media, "text/") || type === String
        isvalid(String, body) || throw(DecodeError("response text is not UTF-8"))
        value = String(copy(body))
        client.validate_responses &&
            _validate_schema(client.spec, 
                schema,
                value,
                "decoding a text response";
                direction = :output,
            )
        return _decode(type, value, client.validate_responses)
    elseif type === Vector{UInt8} || type === Any || media == "application/octet-stream"
        client.validate_responses && _validate_schema(client.spec, 
            schema,
            Base64.base64encode(body),
            "decoding a binary response",
            ; direction = :output,
        )
        return type === Any ? copy(body) :
               _decode(type, body, client.validate_responses)
    end
    throw(UnsupportedMediaType(String(content_type), :response))
end

_form_fields(value::AbstractDict) = Pair{String,Any}[
    String(key) => item for (key, item) in value
]
_form_fields(value::NamedTuple) = Pair{String,Any}[
    String(key) => item for (key, item) in pairs(value)
]
function _form_fields(value)
    encoded = _encode(value)
    encoded isa AbstractDict ||
        throw(ArgumentError("form request body must encode as an object"))
    return Pair{String,Any}[String(key) => item for (key, item) in encoded]
end

function _body_bytes(value, media_type)
    value isa Upload && return copy(value.data)
    value isa AbstractVector{UInt8} && return Vector{UInt8}(value)
    value isa AbstractString && return Vector{UInt8}(codeunits(value))
    throw(
        ArgumentError(
            "codec for $(repr(media_type)) must return a string, byte vector, or Upload",
        ),
    )
end

function _encoded_media_value(client, value, media_type)
    media = _base_media_type(media_type)
    if _is_json_media(media)
        return JSON.json(_encode(value))
    elseif startswith(media, "text/")
        return _scalar(value)
    end
    encoder = _select_media_codec(client.media_encoders, media_type)
    encoder === nothing || return encoder(value, String(media_type))
    value isa Upload && return value.data
    value isa AbstractVector{UInt8} && return value
    value isa AbstractString && return String(value)
    throw(UnsupportedMediaType(String(media_type), :request))
end

function _configured_content_type(configured, preferred = nothing)
    configured === nothing && return preferred
    options = String[
        strip(item) for item in split(String(configured), ',') if !isempty(strip(item))
    ]
    isempty(options) && throw(ArgumentError("encoding contentType is empty"))
    if preferred !== nothing
        any(option -> _media_match(String(preferred), option), options) || throw(
            ArgumentError(
                "part Content-Type $(repr(preferred)) is not allowed by encoding contentType $(repr(configured))",
            ),
        )
        return String(preferred)
    end
    return first(options)
end

function _form_value(client, value, configured_type = nothing)
    if configured_type !== nothing
        selected_type = _configured_content_type(configured_type)
        encoded = _encoded_media_value(client, value, selected_type)
        encoded isa Upload && return Base64.base64encode(encoded.data)
        encoded isa AbstractVector{UInt8} && return Base64.base64encode(encoded)
        return String(encoded)
    end
    value isa Upload && return Base64.base64encode(value.data)
    value isa AbstractVector{UInt8} && return Base64.base64encode(value)
    value isa AbstractDict && return JSON.json(_encode(value))
    value isa NamedTuple && return JSON.json(_encode(value))
    encoded = _encode(value)
    encoded isa AbstractDict && return JSON.json(encoded)
    return _scalar(encoded)
end

function _form_pairs(client, value, encodings)
    output = Tuple{String,String,Bool,Bool}[]
    configured = Dict(encoding.name => encoding for encoding in encodings)
    for (key, item) in _form_fields(value)
        encoding = get(configured, key, nothing)
        if encoding !== nothing && encoding.rfc6570
            style = something(encoding.style, :form)
            explode = something(encoding.explode, style === :form)
            allow_reserved = encoding.allow_reserved
            for (name, encoded, preencoded) in _query_parameter(
                key,
                item,
                style,
                explode,
                allow_reserved,
            )
                push!(
                    output,
                    (name, encoded, allow_reserved, preencoded),
                )
            end
            continue
        end
        configured_type = encoding === nothing ? nothing : encoding.content_type
        if item isa AbstractVector && !(item isa AbstractVector{UInt8})
            for child in item
                push!(
                    output,
                    (String(key), _form_value(client, child, configured_type), false, false),
                )
            end
        else
            push!(
                output,
                (String(key), _form_value(client, item, configured_type), false, false),
            )
        end
    end
    return output
end

_form_escape(value) = replace(_escape(value), "%20" => "+")

function _safe_multipart_text(value, label)
    text = String(value)
    (occursin('\r', text) || occursin('\n', text)) &&
        throw(ArgumentError("multipart $label must not contain CR or LF"))
    return text
end

function _multipart_quoted_text(value, label)
    text = _safe_multipart_text(value, label)
    return replace(
        text,
        Char(92) => string(Char(92), Char(92)),
        Char(34) => string(Char(92), Char(34)),
    )
end

function _multipart_content(
    client,
    value,
    configured_type,
    nested_encodings,
    nested_headers,
)
    has_nested_headers = !isempty(
        _string_keyed_map(nested_headers, "nested multipart_headers"),
    )
    if !isempty(nested_encodings) && configured_type === nothing
        throw(
            ArgumentError(
                "nested Encoding Objects require an explicit multipart or form contentType",
            ),
        )
    end
    if value isa Upload || value isa AbstractVector{UInt8}
        (isempty(nested_encodings) && !has_nested_headers) || throw(
            ArgumentError("binary multipart values cannot contain nested encodings"),
        )
    end
    if value isa Upload
        content_type = something(
            _configured_content_type(configured_type, value.content_type),
            "application/octet-stream",
        )
        return value.data, value.filename, content_type, value.headers
    elseif value isa AbstractVector{UInt8}
        return Vector{UInt8}(value), nothing,
               something(
            _configured_content_type(configured_type),
            "application/octet-stream",
        ),
               Pair{String,String}[]
    elseif configured_type !== nothing
        selected_type = _configured_content_type(configured_type)
        if !isempty(nested_encodings)
            encoded, actual_type = _encode_body(
                client,
                value,
                selected_type,
                nested_encodings;
                multipart_headers = nested_headers,
            )
            return _body_bytes(encoded, actual_type), nothing, actual_type,
                   Pair{String,String}[]
        end
        has_nested_headers && throw(
            ArgumentError("nested multipart headers require nested Encoding Objects"),
        )
        encoded = _encoded_media_value(client, value, selected_type)
        return _body_bytes(encoded, selected_type), nothing, selected_type,
               Pair{String,String}[]
    elseif value isa AbstractString || value isa Number || value isa Bool
        has_nested_headers && throw(
            ArgumentError("nested multipart headers require nested Encoding Objects"),
        )
        return Vector{UInt8}(codeunits(_scalar(value))), nothing,
               something(configured_type, "text/plain"),
               Pair{String,String}[]
    end
    has_nested_headers && throw(
        ArgumentError("nested multipart headers require nested Encoding Objects"),
    )
    return Vector{UInt8}(codeunits(JSON.json(_encode(value)))), nothing,
           something(configured_type, "application/json"),
           Pair{String,String}[]
end

function _multipart_style_pairs(name, value, style, explode)
    encoded = _encode(value)
    if style === :deepObject
        encoded isa AbstractDict || throw(ArgumentError("deepObject requires an object"))
        return Pair{String,Any}[
            string(name, '[', key, ']') => item for (key, item) in _pairs(encoded)
        ]
    elseif style in (:spaceDelimited, :pipeDelimited)
        explode && throw(ArgumentError("$style with explode=true is undefined"))
        delimiter = style === :spaceDelimited ? " " : "|"
        return [String(name) => (encoded isa AbstractDict ?
            _join_object(encoded, delimiter, delimiter) :
            _join_array(encoded, delimiter))]
    elseif style === :form
        if encoded isa AbstractDict
            return explode ?
                   Pair{String,Any}[String(key) => item for (key, item) in _pairs(encoded)] :
                   [String(name) => _join_object(encoded, ",", ",")]
        elseif encoded isa AbstractVector
            return explode ? [String(name) => item for item in encoded] :
                   [String(name) => _join_array(encoded, ",")]
        end
        return [String(name) => encoded]
    end
    throw(ArgumentError("unsupported multipart parameter style $style"))
end

function _string_keyed_map(value, label)
    value isa AbstractDict || value isa NamedTuple || throw(
        ArgumentError("$label must be a dictionary or named tuple"),
    )
    output = Dict{String,Any}()
    for (key, item) in pairs(value)
        name = String(key)
        haskey(output, name) && throw(
            ArgumentError("$label contains duplicate key $(repr(name))"),
        )
        output[name] = item
    end
    return output
end

function _multipart_encoding_headers(client, encoding, supplied)
    supplied_map = _string_keyed_map(supplied, "multipart part headers")
    documented = Dict(lowercase(header.name) => header for header in encoding.headers)
    values = Dict{String,Any}()
    for (name, value) in supplied_map
        lowered = lowercase(name)
        haskey(values, lowered) && throw(
            ArgumentError(
                "multipart part headers contain duplicate case-insensitive name $(repr(name))",
            ),
        )
        descriptor = get(documented, lowered, nothing)
        descriptor === nothing && throw(
            ArgumentError(
                "multipart header $(repr(name)) is not documented for part $(repr(encoding.name))",
            ),
        )
        values[lowered] = value
    end

    output = Pair{String,String}[]
    for descriptor in encoding.headers
        lowered = lowercase(descriptor.name)
        if !haskey(values, lowered)
            descriptor.required && throw(
                ArgumentError(
                    "required multipart header $(repr(descriptor.name)) is missing for part $(repr(encoding.name))",
                ),
            )
            continue
        end
        value = values[lowered]
        _validate_schema(client.spec, 
            descriptor.schema,
            _encode(value),
            "encoding multipart header $(descriptor.name)";
            direction = :input,
        )
        serialized = if isempty(descriptor.content)
            _header_parameter(value, descriptor.explode)
        else
            text, binary = _parameter_content_value(
                client,
                first(descriptor.content),
                value,
            )
            binary && throw(
                ArgumentError(
                    "multipart header content for $(repr(descriptor.name)) must encode as text",
                ),
            )
            text
        end
        push!(output, _safe_header(descriptor.name, serialized))
    end
    return output
end

function _multipart_part_headers(value)
    value isa MultipartPartHeaders && return value.values, value.parts
    return value, NamedTuple()
end

function _merge_multipart_headers(upload_headers, encoding_headers)
    output = Pair{String,String}[]
    seen = Set{String}()
    for (name, value) in Iterators.flatten((upload_headers, encoding_headers))
        lowered = lowercase(String(name))
        lowered in ("content-type", "content-disposition") && throw(
            ArgumentError(
                "multipart part headers must not override Content-Type or Content-Disposition",
            ),
        )
        lowered in seen && throw(
            ArgumentError(
                "multipart part contains duplicate case-insensitive header $(repr(name))",
            ),
        )
        push!(seen, lowered)
        push!(output, _safe_header(name, value))
    end
    return output
end

function _multipart_body(
    client,
    value,
    media_type,
    encodings,
    multipart_headers,
)
    boundary = replace(string(UUIDs.uuid4()), "-" => "")
    configured = Dict(encoding.name => encoding for encoding in encodings)
    supplied = _string_keyed_map(multipart_headers, "multipart_headers")
    used_supplied = Set{String}()
    io = IOBuffer()
    for (name, raw_item) in _form_fields(value)
        encoding = get(configured, name, nothing)
        fields = if encoding !== nothing && encoding.rfc6570
            _multipart_style_pairs(
                name,
                raw_item,
                something(encoding.style, :form),
                something(encoding.explode, true),
            )
        else
            items = raw_item isa AbstractVector &&
                    !(raw_item isa AbstractVector{UInt8}) ? raw_item : (raw_item,)
            Pair{String,Any}[String(name) => item for item in items]
        end
        configured_type = encoding === nothing || encoding.rfc6570 ? nothing :
                          encoding.content_type
        supplied_configuration = get(supplied, name, NamedTuple())
        haskey(supplied, name) && push!(used_supplied, name)
        supplied_headers, nested_headers =
            _multipart_part_headers(supplied_configuration)
        declared_headers = if encoding === nothing
            isempty(_string_keyed_map(supplied_headers, "multipart part headers")) || throw(
                ArgumentError(
                    "multipart headers were supplied for undocumented part $(repr(name))",
                ),
            )
            Pair{String,String}[]
        else
            _multipart_encoding_headers(client, encoding, supplied_headers)
        end
        nested_encodings = encoding === nothing ? () : encoding.encoding
        if encoding === nothing &&
           !isempty(_string_keyed_map(nested_headers, "nested multipart_headers"))
            throw(
                ArgumentError(
                    "nested multipart headers were supplied for undocumented part $(repr(name))",
                ),
            )
        end
        for (part_name, item) in fields
            content, filename, content_type, upload_headers =
                _multipart_content(
                    client,
                    item,
                    configured_type,
                    nested_encodings,
                    nested_headers,
                )
            headers = _merge_multipart_headers(upload_headers, declared_headers)
            safe_name = _multipart_quoted_text(part_name, "part name")
            write(io, "--", boundary, "\r\n")
            write(io, "Content-Disposition: form-data; name=", Char(34), safe_name, Char(34))
            if filename !== nothing
                safe_filename = _multipart_quoted_text(filename, "filename")
                write(io, "; filename=", Char(34), safe_filename, Char(34))
            end
            write(io, "\r\nContent-Type: ", _safe_multipart_text(content_type, "content type"), "\r\n")
            for (header, header_value) in headers
                write(
                    io,
                    _safe_multipart_text(header, "header name"),
                    ": ",
                    _safe_multipart_text(header_value, "header value"),
                    "\r\n",
                )
            end
            write(io, "\r\n", content, "\r\n")
        end
    end
    unused = setdiff(Set(keys(supplied)), used_supplied)
    isempty(unused) || throw(
        ArgumentError(
            "multipart headers were supplied for absent parts: " *
            join(repr.(sort!(collect(unused))), ", "),
        ),
    )
    write(io, "--", boundary, "--\r\n")
    return take!(io), String(media_type) * "; boundary=" * boundary
end


function _encode_body(
    client,
    value,
    media_type,
    encodings;
    multipart_headers = NamedTuple(),
)
    media = _base_media_type(media_type)
    if !startswith(media, "multipart/")
        isempty(_string_keyed_map(multipart_headers, "multipart_headers")) || throw(
            ArgumentError(
                "multipart_headers can only be used with a multipart request body",
            ),
        )
    end
    if _is_json_media(media)
        return JSON.json(_encode(value)), media_type
    elseif _is_sequential_json_media(media)
        return _encode_sequential_json(value, media), media_type
    elseif media == "application/x-www-form-urlencoded"
        pairs = _form_pairs(client, value, encodings)
        body = join(
            (
                _form_escape(key) * "=" *
                (preencoded ? item : replace(
                    _escape(item; allow_reserved),
                    "%20" => "+",
                )) for (key, item, allow_reserved, preencoded) in pairs
            ),
            '&',
        )
        return body, media_type
    elseif startswith(media, "multipart/")
        return _multipart_body(
            client,
            value,
            media_type,
            encodings,
            multipart_headers,
        )
    elseif startswith(media, "text/")
        return value isa AbstractString ? String(value) : _scalar(value), media_type
    end
    return _body_bytes(_encoded_media_value(client, value, media_type), media_type), media_type
end

function _server_for(client::Client, operation)
    if client.server !== nothing
        return String(rstrip(client.server, '/'))
    end
    if client.is_default && client.spec.server[] != client.spec.default_server
        return String(rstrip(client.spec.server[], '/'))
    end
    servers = operation.servers
    isempty(servers) && return client.spec.default_server
    selected = if client.server_name === nothing
        client.server_index <= length(servers) || throw(
            ArgumentError(
                "server index $(client.server_index) exceeds the $(length(servers)) documented servers for $(operation.id)",
            ),
        )
        servers[client.server_index]
    else
        index = findfirst(server -> server.name == client.server_name, servers)
        index === nothing && throw(
            ArgumentError(
                "server name $(repr(client.server_name)) is not documented for $(operation.id)",
            ),
        )
        servers[index]
    end
    url = selected.url
    for variable in selected.variables
        value = get(client.server_variables, variable.name, variable.default)
        isempty(variable.values) || value in variable.values || throw(
            ArgumentError(
                "server variable $(repr(variable.name)) value $(repr(value)) is not in its documented enum",
            ),
        )
        url = replace(url, "{" * variable.name * "}" => value)
    end
    occursin('{', url) && throw(
        ArgumentError("not all server URL variables were supplied for $(operation.id)"),
    )
    if startswith(lowercase(url), "http://") || startswith(lowercase(url), "https://")
        return String(rstrip(url, '/'))
    end
    base = selected.base
    if startswith(lowercase(base), "http://") || startswith(lowercase(base), "https://")
        resolved = SchemaEngine.Resources.URIs.resolvereference(
            SchemaEngine.Resources.URIs.URI(base),
            SchemaEngine.Resources.URIs.URI(url),
        )
        return String(rstrip(string(resolved), '/'))
    end
    return String(rstrip(client.spec.default_server * (startswith(url, '/') ? url : "/" * url), '/'))
end

# Deployed servers routinely omit or misreport Content-Type, so decode by
# status alone unless several documented media types make the choice ambiguous.
# Returns the selected media entry and the media type to decode the body as.
function _selected_media_entry(operation_id, status, descriptor, received)
    selected = isempty(received) ? nothing :
               _select_media(descriptor.media, received)
    selected === nothing || return selected, String(received)
    if isempty(received) || length(descriptor.media) == 1
        entry = first(descriptor.media)
        return entry, entry[1]
    end
    throw(
        UnexpectedContentType(
            operation_id,
            status,
            received,
            Tuple(first.(descriptor.media)),
        ),
    )
end

function _finish_buffered_response(
    client::Client,
    operation,
    status::Int,
    response_headers,
    received,
    bytes::Vector{UInt8},
    with_http_info::Bool,
)
    descriptor = _select_response(operation.responses, status)
    decoded = nothing
    decoded_headers = Dict{String,Any}()
    decode_error = nothing
    try
        decoded_headers = _decode_response_headers(client, descriptor, response_headers)
        if descriptor !== nothing
            if isempty(descriptor.media)
                if !isempty(bytes) && 200 <= status < 300
                    throw(UnexpectedBody(operation.id, status, length(bytes)))
                end
                decoded = nothing
            else
                selected, actual_media =
                    _selected_media_entry(operation.id, status, descriptor, received)
                decoded = _decode_body(
                    client,
                    selected[2],
                    actual_media,
                    bytes,
                    selected[3],
                )
            end
        else
            # The response status is not documented. Specs regularly leave
            # data-less statuses (204, redirects) out, so a successful call
            # must not fail here: surface an empty body as `nothing` and any
            # payload as raw bytes.
            decoded = isempty(bytes) ? nothing : copy(bytes)
        end
    catch error
        200 <= status < 300 && rethrow()
        decode_error = error
    end
    200 <= status < 300 || throw(
        ApiError(
            operation.id,
            status,
            response_headers,
            decoded_headers,
            bytes,
            decoded,
            decode_error,
        ),
    )
    return with_http_info ?
           ApiResponse(status, response_headers, decoded_headers, decoded) :
           decoded
end

# ── streaming responses ──────────────────────────────────────────────────────
#
# Passing `stream_to::Channel` to an operation delivers the response body
# incrementally: the call returns as soon as the response head arrives, a
# background task splits the body into items, decodes each one, and `put!`s it
# on the channel. The channel is closed when the response ends, or closed with
# the error when splitting or decoding fails. Closing the channel from the
# consumer side aborts the transfer.

# How the body is split into items, and what each item decodes to:
# `:json` re-uses the documented response schema per item (concatenated or
# newline-separated JSON documents, e.g. watch-style endpoints); sequential
# JSON media types split records and decode each to the documented array's
# element type; `text/*` yields lines; anything else yields raw byte chunks.
# A registered decoder receives each framed item and the media type it was
# selected for. Its return value is delivered directly, so it can override an
# inaccurate response schema such as a Kubernetes List declaration on a watch
# stream.
function _stream_plan(media, type, schema)
    if _is_sequential_json_media(media)
        item_type = type <: AbstractVector && type !== Vector{UInt8} ?
                    eltype(type) : type
        kind = media == "application/json-seq" || endswith(media, "+json-seq") ?
               :jsonseq : :jsonlines
        # The documented schema describes the whole sequence, not one record,
        # so per-item validation is skipped.
        return kind, item_type, nothing
    elseif _is_json_media(media)
        return :json, type, schema
    elseif startswith(media, "text/") || type === String
        return :text, type, nothing
    end
    return :bytes, Vector{UInt8}, nothing
end

_stream_whitespace(byte::UInt8) =
    byte == 0x20 || byte == 0x09 || byte == 0x0d || byte == 0x0a

function _next_stream_line!(buffer::Vector{UInt8}, final::Bool)
    while !isempty(buffer)
        index = findfirst(==(0x0a), buffer)
        if index === nothing
            final || return nothing
            frame = copy(buffer)
            empty!(buffer)
        else
            frame = buffer[1:index-1]
            deleteat!(buffer, 1:index)
        end
        while !isempty(frame) && frame[end] == 0x0d
            pop!(frame)
        end
        isempty(frame) || return frame
    end
    return nothing
end

# Extract the next complete item from `buffer`, or return `nothing` when more
# bytes are needed. `final` marks the end of the response body.
function _next_stream_frame!(buffer::Vector{UInt8}, kind::Symbol, final::Bool)
    if kind === :jsonseq
        # RFC 7464: records start with RS and may contain unescaped newlines,
        # so a record is complete at the next RS or at the end of the body.
        while true
            start = 1
            while start <= length(buffer) &&
                  (buffer[start] == 0x1e || _stream_whitespace(buffer[start]))
                start += 1
            end
            start > 1 && deleteat!(buffer, 1:start-1)
            isempty(buffer) && return nothing
            index = findfirst(==(0x1e), buffer)
            if index === nothing
                final || return nothing
                frame = copy(buffer)
                empty!(buffer)
            else
                frame = buffer[1:index-1]
                deleteat!(buffer, 1:index-1)
            end
            while !isempty(frame) && _stream_whitespace(frame[end])
                pop!(frame)
            end
            isempty(frame) || return frame
        end
    end
    kind === :json || return _next_stream_line!(buffer, final)
    start = 1
    while start <= length(buffer) &&
          (_stream_whitespace(buffer[start]) || buffer[start] == 0x1e)
        start += 1
    end
    start > 1 && deleteat!(buffer, 1:start-1)
    isempty(buffer) && return nothing
    open_byte = buffer[1]
    if open_byte == UInt8('{') || open_byte == UInt8('[')
        close_byte = open_byte == UInt8('{') ? UInt8('}') : UInt8(']')
        depth = 0
        in_string = false
        escaped = false
        for (index, byte) in enumerate(buffer)
            if escaped
                escaped = false
            elseif in_string
                byte == UInt8('\\') && (escaped = true)
                byte == UInt8('"') && (in_string = false)
            elseif byte == UInt8('"')
                in_string = true
            elseif byte == open_byte
                depth += 1
            elseif byte == close_byte
                depth -= 1
                if depth == 0
                    frame = buffer[1:index]
                    deleteat!(buffer, 1:index)
                    return frame
                end
            end
        end
        return nothing
    end
    # top-level scalar items (numbers, strings, booleans) end at a newline
    return _next_stream_line!(buffer, final)
end

function _decode_stream_item(
    client::Client,
    frame::Vector{UInt8},
    kind::Symbol,
    item_type,
    schema,
    media_type,
)
    decoder = _select_media_codec(client.media_decoders, media_type)
    decoder === nothing || return decoder(copy(frame), String(media_type))
    if kind === :text
        isvalid(String, frame) ||
            throw(DecodeError("streaming text response is not UTF-8"))
        return _decode(item_type, String(frame), client.validate_responses)
    end
    kind === :bytes && return copy(frame)
    value = _parse_json(frame, "decoding a streaming response item")
    schema === nothing || !client.validate_responses || _validate_schema(client.spec, 
        schema,
        value,
        "decoding a streaming response item";
        direction = :output,
    )
    return _decode(item_type, value, client.validate_responses)
end

# Deployed watch-style servers reply with the bare media type — the Kubernetes
# apiserver sends `Content-Type: application/json` even when the request
# selected `application/json;stream=watch` — which never matches a codec
# registered for the parameterized variant. When no decoder matches the
# received media type, fall back to the media type the caller explicitly
# requested via `accept`, so a parameterized registration fires for exactly
# the calls that asked for that variant.
function _stream_codec_media(client::Client, media_type, accept)
    media = String(media_type)
    accept === nothing && return media
    _select_media_codec(client.media_decoders, media) === nothing || return media
    base = first(_media_type(media))
    for option in split(String(accept), ',')
        candidate = String(strip(option))
        isempty(candidate) && continue
        first(_media_type(candidate)) == base || continue
        _select_media_codec(client.media_decoders, candidate) === nothing ||
            return candidate
    end
    return media
end

function _drain_stream_buffer!(
    client::Client,
    channel::Channel,
    buffer::Vector{UInt8},
    kind::Symbol,
    item_type,
    schema,
    media_type,
    final::Bool,
)
    while true
        frame = _next_stream_frame!(buffer, kind, final)
        frame === nothing && break
        put!(
            channel,
            _decode_stream_item(client, frame, kind, item_type, schema, media_type),
        )
    end
    final && kind === :json && !all(_stream_whitespace, buffer) &&
        throw(DecodeError("streaming response ended with a truncated item"))
    return nothing
end

end # module Runtime
