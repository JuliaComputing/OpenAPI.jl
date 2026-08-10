const GENERATED_RUNTIME_COMMON = raw"""
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

const _SCHEMA_GRAPHS = Dict{Symbol,Any}()
const _SCHEMA_GRAPH_LOCK = ReentrantLock()

function _schema_graph(direction::Symbol = :neutral)
    direction in (:neutral, :input, :output) ||
        throw(ArgumentError("schema direction must be :neutral, :input, or :output"))
    isempty(_SCHEMA_ROOT_DATA) && return nothing
    haskey(_SCHEMA_GRAPHS, direction) && return _SCHEMA_GRAPHS[direction]
    return lock(_SCHEMA_GRAPH_LOCK) do
        haskey(_SCHEMA_GRAPHS, direction) && return _SCHEMA_GRAPHS[direction]
        documents = Dict{String,Any}(
            entry.id => JSON.parse(entry.json; duplicate_keys = :error) for
            entry in _SCHEMA_RESOURCE_DATA
        )
        if direction !== :neutral
            for rule in _SCHEMA_DIRECTIONAL_REQUIRED
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
        for entry in _SCHEMA_RESOURCE_DATA
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
            ) for entry in _SCHEMA_ROOT_DATA
        ]
        root_dialects = Dict(
            root => entry.dialect for (root, entry) in zip(roots, _SCHEMA_ROOT_DATA)
        )
        dialect_aliases = Dict(
            entry.uri => SchemaEngine.Dialect(
                entry.name,
                entry.uri,
                entry.id_keyword,
                entry.ref_siblings,
                entry.modern_items,
                entry.unevaluated,
                entry.dynamic_refs,
                entry.recursive_refs,
                entry.applicator,
                entry.validation,
            ) for entry in _SCHEMA_DIALECT_DATA
        )
        graph = SchemaEngine.CompiledSchemas(
            resources,
            roots;
            dialect = SchemaEngine.DRAFT202012,
            root_dialects,
            dialect_aliases,
        )
        _SCHEMA_GRAPHS[direction] = graph
        return graph
    end
end

function _schema_at(descriptor, direction::Symbol = :neutral)
    descriptor === nothing && return nothing
    graph = _schema_graph(direction)
    graph === nothing && return nothing
    node = SchemaEngine.Resources.NodeId(
        SchemaEngine.Resources.ResourceId(descriptor.resource),
        SchemaEngine.Resources.JSONPointer(descriptor.pointer),
    )
    return SchemaEngine.subschema(graph, node)
end

function _schema_issues(descriptor, value; direction::Symbol = :neutral)
    schema = _schema_at(descriptor, direction)
    schema === nothing && return Any[]
    return Any[SchemaEngine.validate(schema, value; fail_fast = false)...]
end

function _validate_schema(
    descriptor,
    value,
    context;
    direction::Symbol = :neutral,
)
    issues = _schema_issues(descriptor, value; direction)
    isempty(issues) || throw(SchemaValidationError(String(context), issues))
    return value
end

_schema_valid(descriptor, value; direction::Symbol = :neutral) =
    isempty(_schema_issues(descriptor, value; direction))

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
"""

# Emitted only for `datetime = :zoned` plans, directly after
# GENERATED_RUNTIME_COMMON, in both generated clients and servers.
const GENERATED_ZONED_RUNTIME = raw"""
function _decode(::Type{TimeZones.ZonedDateTime}, value::AbstractString)
    matched = match(
        r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})?$",
        value,
    )
    matched === nothing && throw(DecodeError("invalid RFC 3339 date-time $(repr(value))"))
    try
        clock = Dates.DateTime(matched.captures[1])
        fraction = matched.captures[2]
        if fraction !== nothing
            clock += Dates.Millisecond(
                parse(Int, rpad(first(fraction, min(3, length(fraction))), 3, '0')),
            )
        end
        zone = matched.captures[3]
        timezone = if zone === nothing || zone == "Z"
            TimeZones.tz"UTC"
        else
            sign = startswith(zone, '+') ? 1 : -1
            hours = parse(Int, zone[2:3])
            minutes = parse(Int, zone[5:6])
            TimeZones.FixedTimeZone(zone, sign * (3600 * hours + 60 * minutes))
        end
        return TimeZones.ZonedDateTime(clock, timezone)
    catch error
        error isa DecodeError && rethrow()
        throw(DecodeError("invalid RFC 3339 date-time: $(sprint(showerror, error))"))
    end
end
_encode(value::TimeZones.ZonedDateTime) =
    Dates.format(value, TimeZones.ISOZonedDateTimeFormat)
"""

const GENERATED_RUNTIME = raw"""
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
    server::Union{Nothing,AbstractString} = nothing;
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
credential!(name::AbstractString, credential::AbstractCredential) =
    credential!(DEFAULT_CLIENT, name, credential)

function clearcredential!(client::Client, name::AbstractString)
    delete!(client.credentials, String(name))
    return client
end
clearcredential!(name::AbstractString) = clearcredential!(DEFAULT_CLIENT, name)

function server!(client::Client, server::Union{Nothing,AbstractString})
    client.server = server === nothing ? nothing : String(rstrip(server, '/'))
    isdefined(@__MODULE__, :DEFAULT_CLIENT) && client === DEFAULT_CLIENT &&
        (SERVER[] = something(client.server, _DEFAULT_SERVER))
    return client
end
server!(server::Union{Nothing,AbstractString}) = server!(DEFAULT_CLIENT, server)

function server_index!(client::Client, index::Integer)
    index > 0 || throw(ArgumentError("server index must be positive"))
    client.server_index = Int(index)
    client.server_name = nothing
    return client
end
server_index!(index::Integer) = server_index!(DEFAULT_CLIENT, index)

function server_name!(client::Client, name::Union{Nothing,AbstractString})
    client.server_name = name === nothing ? nothing : String(name)
    return client
end
server_name!(name::Union{Nothing,AbstractString}) = server_name!(DEFAULT_CLIENT, name)

function server_variable!(client::Client, name::AbstractString, value::AbstractString)
    client.server_variables[String(name)] = String(value)
    return client
end
server_variable!(name::AbstractString, value::AbstractString) =
    server_variable!(DEFAULT_CLIENT, name, value)

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
codec!(media_type::AbstractString; kwargs...) =
    codec!(DEFAULT_CLIENT, media_type; kwargs...)

function authorization!(client::Client, token::Union{Nothing,AbstractString})
    names = String[
        name for (name, scheme) in _SECURITY_SCHEMES
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
authorization!(token::Union{Nothing,AbstractString}) = authorization!(DEFAULT_CLIENT, token)

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

_is_hex_digit(char) = isdigit(char) || 'a' <= lowercase(char) <= 'f'

function _escape(value; allow_reserved::Bool = false)
    text = String(value)
    allow_reserved || return HTTP.escapeuri(text)
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
            write(io, HTTP.escapeuri(string(char)))
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
            scheme = get(_SECURITY_SCHEMES, entry[1], nothing)
            return scheme !== nothing &&
                   _credential_satisfies(scheme, credential, entry[2])
        end || continue
        options = base_options
        for (name, _) in requirement
            scheme = _SECURITY_SCHEMES[name]
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
            _decode_schema_header(
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
            _validate_schema(
                schema,
                lowered,
                "decoding a custom-media response";
                direction = :output,
            )
        return _decode(type, lowered, client.validate_responses)
    elseif _is_json_media(media)
        if isempty(body)
            client.validate_responses &&
                _validate_schema(
                    schema,
                    nothing,
                    "decoding an empty JSON response";
                    direction = :output,
                )
            return _decode(type, nothing, client.validate_responses)
        end
        value = _parse_json(body, "decoding a response")
        client.validate_responses &&
            _validate_schema(
                schema,
                value,
                "decoding a JSON response";
                direction = :output,
            )
        return _decode(type, value, client.validate_responses)
    elseif _is_sequential_json_media(media)
        value = _decode_sequential_json(body, media)
        client.validate_responses &&
            _validate_schema(
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
            _validate_schema(
                schema,
                value,
                "decoding a text response";
                direction = :output,
            )
        return _decode(type, value, client.validate_responses)
    elseif type === Vector{UInt8} || type === Any || media == "application/octet-stream"
        client.validate_responses && _validate_schema(
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
        _validate_schema(
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
    if client === DEFAULT_CLIENT && SERVER[] != _DEFAULT_SERVER
        return String(rstrip(SERVER[], '/'))
    end
    servers = operation.servers
    isempty(servers) && return _DEFAULT_SERVER
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
    return String(rstrip(_DEFAULT_SERVER * (startswith(url, '/') ? url : "/" * url), '/'))
end

function _request(
    client::Client,
    operation,
    values::Dict{Symbol,Any};
    body = ABSENT,
    content_type = nothing,
    accept = nothing,
    with_http_info::Bool = false,
    request_headers = Pair{String,String}[],
    request_options::NamedTuple = NamedTuple(),
    multipart_headers = NamedTuple(),
    stream_to::Union{Nothing,Channel} = nothing,
)
    path = operation.path
    query = Tuple{String,String,Bool,Bool}[]
    headers = Pair{String,String}[_safe_header(key, value) for (key, value) in client.headers]
    for (key, value) in request_headers
        _set_header!(headers, key, value)
    end
    cookies = Tuple{String,String,Bool,Bool}[]
    for descriptor in operation.parameters
        value = get(values, descriptor.arg, ABSENT)
        if value isa Absent
            descriptor.required &&
                throw(ArgumentError("required parameter $(descriptor.name) is missing"))
            continue
        end
        client.validate_requests && _validate_schema(
            descriptor.schema,
            _encode(value),
            "encoding parameter $(descriptor.name)";
            direction = :input,
        )
        path = _append_parameter!(
            client,
            path,
            query,
            headers,
            cookies,
            descriptor,
            value,
        )
    end
    occursin('{', path) &&
        throw(ArgumentError("not all path template parameters were supplied for $(operation.id)"))
    default_options = stream_to isa Channel ? (; protocol = :h1) : NamedTuple()
    base_options = merge(default_options, client.request_options, request_options)
    options = _security!(
        client,
        operation.security,
        query,
        headers,
        cookies,
        base_options,
    )
    if !isempty(cookies)
        cookie_text = join(
            (
                fragment ? key :
                (raw ? key : _escape(key)) * "=" *
                (raw ? value : _escape(value)) for
                (key, value, raw, fragment) in cookies
            ),
            "; ",
        )
        existing = join(_header_values(headers, "Cookie"), "; ")
        _set_header!(
            headers,
            "Cookie",
            isempty(existing) ? cookie_text : existing * "; " * cookie_text,
        )
        options = merge(options, (; cookies = false))
    end
    query_text = isempty(query) ? "" : "?" * join(
        (
            _escape(key) * "=" *
            (preencoded ? value : _escape(value; allow_reserved)) for
            (key, value, allow_reserved, preencoded) in query
        ),
        '&',
    )
    url = _server_for(client, operation) *
          (startswith(path, '/') ? path : "/" * path) * query_text

    payload = UInt8[]
    if operation.request !== nothing && !(body isa Absent)
        media = operation.request.media
        entry = content_type === nothing ? first(media) :
                _select_media(media, String(content_type))
        entry === nothing && throw(
            ArgumentError("unsupported request Content-Type $(repr(content_type)) for $(operation.id)"),
        )
        client.validate_requests && _validate_schema(
            entry[3],
            _encode(body),
            "encoding the $(operation.id) request body";
            direction = :input,
        )
        payload, actual_content_type =
            _encode_body(
                client,
                body,
                entry[1],
                entry[4];
                multipart_headers,
            )
        _set_header!(headers, "Content-Type", actual_content_type)
    elseif operation.request !== nothing && operation.request.required
        throw(ArgumentError("required request body is missing for $(operation.id)"))
    end
    documented_accept = String[
        entry[1] for response in operation.responses for entry in response.media
        if startswith(uppercase(response.selector), "2") ||
           uppercase(response.selector) == "DEFAULT"
    ]
    existing_accept = _header_values(headers, "Accept")
    selected_accept = if accept !== nothing
        String(accept)
    elseif !isempty(existing_accept)
        nothing
    else
        join(unique(documented_accept), ", ")
    end
    selected_accept === nothing || isempty(selected_accept) ||
        _set_header!(headers, "Accept", selected_accept)

    stream_to === nothing || return _stream_request(
        client,
        operation,
        url,
        headers,
        payload,
        options,
        stream_to,
        with_http_info,
    )
    options = merge(options, (body = payload, status_exception = false))
    response = HTTP.request(
        operation.method,
        url,
        headers;
        options...,
    )
    response_headers = Pair{String,String}[
        String(key) => String(value) for (key, value) in response.headers
    ]
    return _finish_buffered_response(
        client,
        operation,
        Int(response.status),
        response_headers,
        HTTP.header(response, "Content-Type", ""),
        Vector{UInt8}(response.body),
        with_http_info,
    )
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
# A registered decoder receives each framed item and its actual Content-Type.
# Its return value is delivered directly, so it can override an inaccurate
# response schema such as a Kubernetes List declaration on a watch stream.
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
    schema === nothing || !client.validate_responses || _validate_schema(
        schema,
        value,
        "decoding a streaming response item";
        direction = :output,
    )
    return _decode(item_type, value, client.validate_responses)
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

function _pump_stream!(
    client::Client,
    stream,
    channel::Channel,
    kind::Symbol,
    item_type,
    schema,
    media_type,
    finished,
)
    buffer = UInt8[]
    try
        while !eof(stream)
            chunk = readavailable(stream)
            isempty(chunk) && continue
            if kind === :bytes
                put!(
                    channel,
                    _decode_stream_item(
                        client,
                        chunk,
                        kind,
                        item_type,
                        schema,
                        media_type,
                    ),
                )
            else
                append!(buffer, chunk)
                _drain_stream_buffer!(
                    client,
                    channel,
                    buffer,
                    kind,
                    item_type,
                    schema,
                    media_type,
                    false,
                )
            end
        end
        kind === :bytes || _drain_stream_buffer!(
            client,
            channel,
            buffer,
            kind,
            item_type,
            schema,
            media_type,
            true,
        )
        finished[] = true
        close(channel)
    catch error
        # A channel the consumer closed is the abort signal; anything else is
        # delivered to the consumer through the channel.
        if isopen(channel)
            finished[] = true
            close(channel, error)
        end
    finally
        try
            HTTP.closeread(stream)
        catch
        end
        finished[] = true
    end
    return nothing
end

function _abort_stream_on_close!(stream, channel::Channel, producer::Task, finished)
    while isopen(channel) && !finished[]
        sleep(0.25)
    end
    finished[] && return nothing
    try
        HTTP.closeread(stream)
    catch
    end
    for _ in 1:4
        istaskdone(producer) && return nothing
        sleep(0.25)
    end
    try
        close(stream)
    catch
    end
    return nothing
end

function _stream_request(
    client::Client,
    operation,
    url,
    headers,
    payload::Vector{UInt8},
    options,
    stream_to::Channel,
    with_http_info::Bool,
)
    stream = HTTP.open(operation.method, url, headers; options...)
    local response
    try
        isempty(payload) || write(stream, payload)
        HTTP.closewrite(stream)
        response = HTTP.startread(stream)
    catch
        try
            HTTP.closeread(stream)
        catch
        end
        rethrow()
    end
    response_headers = Pair{String,String}[
        String(key) => String(value) for (key, value) in response.headers
    ]
    received = HTTP.header(response, "Content-Type", "")
    status = Int(response.status)
    if !(200 <= status < 300)
        bytes = try
            read(stream)
        finally
            try
                HTTP.closeread(stream)
            catch
            end
        end
        # Throws ApiError with the fully decoded error body.
        return _finish_buffered_response(
            client,
            operation,
            status,
            response_headers,
            received,
            bytes,
            with_http_info,
        )
    end
    local descriptor, decoded_headers, kind, item_type, schema, actual_media
    try
        descriptor = _select_response(operation.responses, status)
        decoded_headers = _decode_response_headers(client, descriptor, response_headers)
        if descriptor === nothing || isempty(descriptor.media)
            actual_media = isempty(received) ? "application/octet-stream" : String(received)
            kind, item_type, schema = :bytes, Vector{UInt8}, nothing
        else
            selected, actual_media =
                _selected_media_entry(operation.id, status, descriptor, received)
            kind, item_type, schema =
                _stream_plan(_base_media_type(actual_media), selected[2], selected[3])
        end
    catch
        try
            HTTP.closeread(stream)
        catch
        end
        rethrow()
    end
    finished = Ref(false)
    producer = errormonitor(@async _pump_stream!(
        client,
        stream,
        stream_to,
        kind,
        item_type,
        schema,
        actual_media,
        finished,
    ))
    errormonitor(@async _abort_stream_on_close!(stream, stream_to, producer, finished))
    return with_http_info ?
           ApiResponse(status, response_headers, decoded_headers, stream_to) :
           stream_to
end
"""

function _julia_literal(value)
    Base.@nospecialize value
    value === nothing && return "nothing"
    value isa Symbol && return repr(value)
    value isa AbstractString && return repr(String(value))
    value isa Bool && return value ? "true" : "false"
    value isa Integer && return repr(value)
    value isa AbstractFloat && return repr(value)
    if value isa Tuple || value isa AbstractVector
        items = String[_julia_literal(item) for item in value]
        return "(" * join(items, ',') * (length(items) == 1 ? "," : "") * ")"
    elseif value isa Pair
        return _julia_literal(value.first) * " => " * _julia_literal(value.second)
    end
    return repr(value)
end

function _http_retrieval_base(resource; include_path::Bool = true)
    uri = resource.retrieval.uri
    scheme = lowercase(uri.scheme)
    scheme in ("http", "https") || return nothing
    isempty(uri.host) && return nothing
    host = occursin(':', uri.host) && !startswith(uri.host, '[') ?
           "[" * uri.host * "]" : uri.host
    authority = scheme * "://" * host *
                (isempty(uri.port) ? "" : ":" * uri.port)
    include_path || return authority
    return authority * (isempty(uri.path) ? "/" : uri.path)
end

function _default_server(api::NormalizedAPI)
    if isempty(api.servers)
        return something(
            _http_retrieval_base(api.source.resource; include_path = false),
            "http://127.0.0.1:8080",
        )
    end
    server = first(api.servers)
    url = server.url
    for variable in server.variables
        url = replace(url, "{" * variable.name * "}" => variable.default)
    end
    if startswith(url, "http://") || startswith(url, "https://")
        return String(rstrip(url, '/'))
    end
    resource = Resources.resource(api.registry, server.provenance.node.resource)
    retrieval = _http_retrieval_base(resource)
    if retrieval !== nothing
        resolved = Resources.URIs.resolvereference(
            Resources.URIs.URI(retrieval),
            Resources.URIs.URI(url),
        )
        return String(rstrip(string(resolved), '/'))
    end
    return String(
        rstrip(
            "http://127.0.0.1:8080" * (startswith(url, '/') ? url : "/" * url),
            '/',
        ),
    )
end

function _server_descriptor(
    servers,
    api::NormalizedAPI,
    fallback::Resources.NodeId,
)
    Base.@nospecialize servers
    if isempty(servers)
        resource = Resources.resource(api.registry, fallback.resource)
        return "((name = nothing, url = \"/\", base = " *
               _julia_literal(something(_http_retrieval_base(resource), "")) *
               ", variables = ()),)"
    end
    entries = String[]
    for server in servers
        resource = Resources.resource(api.registry, server.provenance.node.resource)
        variables = String[
            "(name = " * repr(variable.name) *
            ", default = " * repr(variable.default) *
            ", values = " * _julia_literal(variable.values) * ")" for
            variable in server.variables
        ]
        encoded_variables = "(" * join(variables, ',') *
                            (length(variables) == 1 ? "," : "") * ")"
        push!(
            entries,
            "(name = " * _julia_literal(server.name) *
            ", url = " * repr(server.url) *
            ", base = " * _julia_literal(
                startswith(lowercase(server.url), "http://") ||
                startswith(lowercase(server.url), "https://") ? "" :
                something(_http_retrieval_base(resource), ""),
            ) *
            ", variables = " * encoded_variables * ")",
        )
    end
    return "(" * join(entries, ',') * (length(entries) == 1 ? "," : "") * ")"
end

function _security_type(scheme::NormalizedSecurityScheme)
    if scheme.type === :http
        lowered = lowercase(something(scheme.scheme, ""))
        lowered == "basic" && return :http_basic
        lowered == "bearer" && return :http_bearer
        return :http
    elseif scheme.type in (:openidconnect, :open_id_connect)
        return :openidconnect
    elseif scheme.type in (:mutualtls, :mutual_tls)
        return :mutualtls
    end
    return scheme.type
end

function _emit_security(io::IO, plan::GenerationPlan)
    println(io, "const _SECURITY_SCHEMES = Dict{String,NamedTuple}(")
    for scheme in sort(collect(plan.api.security_schemes); by = item -> item.name)
        print(io, "    ", repr(scheme.name), " => (")
        print(io, "type = ", repr(_security_type(scheme)), ", ")
        print(io, "location = ", repr(something(scheme.location, :none)), ", ")
        print(io, "name = ", repr(something(scheme.parameter_name, "")), ", ")
        println(io, "scheme = ", repr(something(scheme.scheme, "")), "),")
    end
    println(io, ")\n")
end

function _model_indices(plan::GenerationPlan)
    return Dict(model.name => index for (index, model) in enumerate(plan.models))
end

function _model_references(type::String, names)
    output = String[]
    for matched in eachmatch(r"[A-Za-z_][A-Za-z0-9_]*", type)
        name = matched.match
        name in names || continue
        name in output || push!(output, name)
    end
    return output
end

function _cyclic_aliases(plan::GenerationPlan)
    aliases = Set(model.name for model in plan.models if model.kind === :alias)
    edges = Dict(
        model.name => _model_references(something(model.alias, ""), aliases) for
        model in plan.models if model.kind === :alias
    )
    function reaches(start, current, seen)
        current in seen && return false
        push!(seen, current)
        for target in get(edges, current, String[])
            target == start && return true
            reaches(start, target, seen) && return true
        end
        return false
    end
    return Set(name for name in aliases if reaches(name, name, Set{String}()))
end

function _model_types(model::ModelPlan, wrapped_aliases)
    if model.kind === :object
        types = String[field.type for field in model.fields]
        model.additional_type === nothing || push!(types, model.additional_type)
        return types
    elseif model.kind in (:oneof, :anyof)
        return String[something(model.alias, "Any")]
    elseif model.kind === :alias && model.name in wrapped_aliases
        return String[something(model.alias, "Any")]
    end
    return String[]
end

function _forward_abstracts(plan::GenerationPlan, wrapped_aliases)
    indices = _model_indices(plan)
    concrete = Set(model.name for model in plan.models if model.kind !== :alias)
    union!(concrete, wrapped_aliases)
    targets = copy(wrapped_aliases)
    for (index, model) in enumerate(plan.models)
        for type in _model_types(model, wrapped_aliases), target in _model_references(type, concrete)
            get(indices, target, 0) > index && push!(targets, target)
        end
    end
    return targets
end

function _rewrite_forward(type::String, index::Int, indices, targets)
    output = type
    for target in _model_references(type, targets)
        get(indices, target, 0) > index || continue
        output = replace(output, Regex("\\b" * target * "\\b") => "Abstract" * target)
    end
    return output
end

function _emit_model(
    io::IO,
    model::ModelPlan,
    index,
    indices,
    abstract_targets,
    wrapped_aliases,
)
    schema = _schema_descriptor(model.provenance.node)
    direction = repr(model.direction)
    if model.kind === :alias && model.name in wrapped_aliases
        type = _rewrite_forward(model.alias, index, indices, abstract_targets)
        supertype = model.name in abstract_targets ? " <: Abstract" * model.name : ""
        println(io, "struct ", model.name, supertype)
        println(io, "    value::", type)
        println(io, "end")
        model.name in abstract_targets && println(
            io,
            "_decode(::Type{Abstract",
            model.name,
            "}, value) = _decode(",
            model.name,
            ", value)",
        )
        model.name in abstract_targets && println(
            io,
            "_decode(::Type{Abstract",
            model.name,
            "}, value, validate::Bool) = _decode(",
            model.name,
            ", value, validate)",
        )
        println(io, "_decode(::Type{", model.name, "}, value) = _decode(", model.name, ", value, true)")
        println(io, "function _decode(::Type{", model.name, "}, value, _openapi_validate::Bool)")
        println(io, "    _openapi_validate && _validate_schema(", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
        println(io, "    return ", model.name, "(_decode(", type, ", value, _openapi_validate))")
        println(io, "end")
        println(io, "function _encode(value::", model.name, ")")
        println(io, "    output = _encode(value.value)")
        println(io, "    return _validate_schema(", schema, ", output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
        println(io, "end\n")
        return
    elseif model.kind === :alias
        println(io, "const ", model.name, " = ", model.alias, "\n")
        return
    elseif model.kind === :enum
        supertype = model.name in abstract_targets ? " <: Abstract" * model.name : ""
        println(io, "struct ", model.name, supertype)
        println(io, "    value::", model.alias)
        println(io, "    function ", model.name, "(value::", model.alias, ")")
        println(io, "        value in ", _julia_literal(model.values), " || throw(ArgumentError(\"invalid ", model.name, " value \$(repr(value))\"))")
        println(io, "        return new(value)")
        println(io, "    end")
        println(io, "end")
        model.name in abstract_targets && println(
            io,
            "_decode(::Type{Abstract",
            model.name,
            "}, value) = _decode(",
            model.name,
            ", value)",
        )
        model.name in abstract_targets && println(
            io,
            "_decode(::Type{Abstract",
            model.name,
            "}, value, validate::Bool) = _decode(",
            model.name,
            ", value, validate)",
        )
        println(io, "_decode(::Type{", model.name, "}, value) = _decode(", model.name, ", value, true)")
        println(io, "function _decode(::Type{", model.name, "}, value, _openapi_validate::Bool)")
        println(io, "    _openapi_validate && _validate_schema(", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
        println(io, "    return ", model.name, "(_decode(", model.alias, ", value, _openapi_validate))")
        println(io, "end")
        println(io, "function _encode(value::", model.name, ")")
        println(io, "    output = _encode(value.value)")
        println(io, "    return _validate_schema(", schema, ", output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
        println(io, "end")
        println(io, "Base.string(value::", model.name, ") = string(value.value)\n")
        return
    elseif model.kind in (:oneof, :anyof)
        type = _rewrite_forward(model.alias, index, indices, abstract_targets)
        supertype = model.name in abstract_targets ? " <: Abstract" * model.name : ""
        println(io, "struct ", model.name, supertype)
        println(io, "    value::", type)
        println(io, "end")
        model.name in abstract_targets && println(
            io,
            "_decode(::Type{Abstract",
            model.name,
            "}, value) = _decode(",
            model.name,
            ", value)",
        )
        model.name in abstract_targets && println(
            io,
            "_decode(::Type{Abstract",
            model.name,
            "}, value, validate::Bool) = _decode(",
            model.name,
            ", value, validate)",
        )
        if model.discriminator !== nothing &&
           (!isempty(model.discriminator_mapping) || model.discriminator_default !== nothing)
            println(io, "_decode(::Type{", model.name, "}, value) = _decode(", model.name, ", value, true)")
            println(io, "function _decode(::Type{", model.name, "}, value, _openapi_validate::Bool)")
            println(io, "    _openapi_validate && _validate_schema(", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
            println(io, "    object = _object(value, ", repr(model.name), ")")
            println(io, "    tag = get(object, ", repr(model.discriminator), ", ABSENT)")
            println(io, "    tag isa Absent || tag isa AbstractString || throw(DecodeError(\"discriminator value must be a string for ", model.name, "\"))")
            println(io, "    selected = get(Dict(")
            for (tag, target) in model.discriminator_mapping
                node, type = target
                println(
                    io,
                    "        ",
                    repr(tag),
                    " => (",
                    type,
                    ", ",
                    _schema_descriptor(node),
                    "),",
                )
            end
            println(io, "    ), tag isa Absent ? \"\" : String(tag), nothing)")
            if model.discriminator_default !== nothing
                node, type = model.discriminator_default
                println(
                    io,
                    "    selected === nothing && (selected = (",
                    type,
                    ", ",
                    _schema_descriptor(node),
                    "))",
                )
            end
            println(io, "    selected === nothing && throw(DecodeError(\"unknown discriminator value \$(repr(tag)) for ", model.name, "\"))")
            println(io, "    !_openapi_validate || _schema_valid(selected[2], value; direction = ", direction, ") || throw(DecodeError(\"discriminator-selected schema did not validate for ", model.name, "\"))")
            println(io, "    return ", model.name, "(_decode(selected[1], value, _openapi_validate))")
            println(io, "end")
        else
            println(io, "_decode(::Type{", model.name, "}, value) = _decode(", model.name, ", value, true)")
            println(io, "function _decode(::Type{", model.name, "}, value, _openapi_validate::Bool)")
            println(io, "    _openapi_validate && _validate_schema(", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
            "Nothing" in model.values && println(
                io,
                "    value === nothing && return ",
                model.name,
                "(nothing)",
            )
            println(io, "    matches = Any[]")
            for (node, type) in model.variants
                descriptor = _schema_descriptor(node)
                println(io, "    if !_openapi_validate || _schema_valid(", descriptor, ", value; direction = ", direction, ")")
                println(io, "        try")
                println(io, "            push!(matches, _decode(", type, ", value, _openapi_validate))")
                println(io, "        catch error")
                println(io, "            error isa DecodeError || rethrow()")
                println(io, "        end")
                println(io, "    end")
            end
            if model.kind === :oneof
                println(io, "    length(matches) == 1 || throw(DecodeError(\"oneOf value did not select exactly one variant of ", model.name, "\"))")
            else
                println(io, "    isempty(matches) && throw(DecodeError(\"anyOf value did not select a variant of ", model.name, "\"))")
            end
            println(io, "    return ", model.name, "(first(matches))")
            println(io, "end")
        end
        println(io, "function _encode(value::", model.name, ")")
        println(io, "    output = _encode(value.value)")
        println(io, "    return _validate_schema(", schema, ", output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
        println(io, "end\n")
        return
    end

    supertype = model.name in abstract_targets ? " <: Abstract" * model.name : ""
    println(io, "Base.@kwdef struct ", model.name, supertype)
    for field in model.fields
        type = _rewrite_forward(field.type, index, indices, abstract_targets)
        print(io, "    ", field.name, "::", type)
        field.default === nothing || print(io, " = ", field.default)
        println(io)
    end
    if model.additional_type !== nothing
        additional_type = _rewrite_forward(
            model.additional_type,
            index,
            indices,
            abstract_targets,
        )
        println(
            io,
            "    additional_properties::Dict{String,",
            additional_type,
            "} = Dict{String,",
            additional_type,
            "}()",
        )
    end
    println(io, "end")
    model.name in abstract_targets && println(
        io,
        "_decode(::Type{Abstract",
        model.name,
        "}, value) = _decode(",
        model.name,
        ", value)",
    )
    model.name in abstract_targets && println(
        io,
        "_decode(::Type{Abstract",
        model.name,
        "}, value, validate::Bool) = _decode(",
        model.name,
        ", value, validate)",
    )
    println(io, "_decode(::Type{", model.name, "}, value) = _decode(", model.name, ", value, true)")
    println(io, "function _decode(::Type{", model.name, "}, _openapi_raw, _openapi_validate::Bool)")
    println(io, "    _openapi_validate && _validate_schema(", schema, ", _openapi_raw, ", repr("decoding " * model.name), "; direction = ", direction, ")")
    println(io, "    _openapi_object = _object(_openapi_raw, ", repr(model.name), ")")
    for field in model.fields
        type = _rewrite_forward(field.type, index, indices, abstract_targets)
        local_name = "_openapi_field_" * field.name
        if field.required
            println(
                io,
                "    ",
                local_name,
                " = _decode(",
                type,
                ", _required(_openapi_object, ",
                repr(field.wire_name),
                ", ",
                repr(model.name),
                "), _openapi_validate)",
            )
        else
            println(
                io,
                "    ",
                local_name,
                " = haskey(_openapi_object, ",
                repr(field.wire_name),
                ") ? _decode(",
                type,
                ", _openapi_object[",
                repr(field.wire_name),
                "], _openapi_validate) : ABSENT",
            )
        end
    end
    known = Tuple(field.wire_name for field in model.fields)
    if model.additional_type !== nothing
        additional_type = _rewrite_forward(model.additional_type, index, indices, abstract_targets)
        println(io, "    _openapi_additional_properties = Dict{String,", additional_type, "}()")
        println(io, "    for (_openapi_key, _openapi_item) in _openapi_object")
        println(io, "        String(_openapi_key) in ", _julia_literal(known), " && continue")
        println(io, "        _openapi_additional_properties[String(_openapi_key)] = _decode(", additional_type, ", _openapi_item, _openapi_validate)")
        println(io, "    end")
    else
        println(io, "    _openapi_unknown = setdiff(String.(collect(keys(_openapi_object))), collect(", _julia_literal(known), "))")
        println(io, "    !_openapi_validate || isempty(_openapi_unknown) || throw(DecodeError(\"unknown fields while decoding ", model.name, ": \" * join(_openapi_unknown, \", \")))")
    end
    print(io, "    return ", model.name, "(")
    assignments = String[
        string(field.name, " = _openapi_field_", field.name) for field in model.fields
    ]
    model.additional_type === nothing || push!(assignments, "additional_properties = _openapi_additional_properties")
    println(io, "; ", join(assignments, ", "), ")")
    println(io, "end")
    println(io, "function _encode(_openapi_value::", model.name, ")")
    println(io, "    _openapi_output = JSON.Object{String,Any}()")
    for field in model.fields
        println(io, "    _openapi_value.", field.name, " isa Absent || (_openapi_output[", repr(field.wire_name), "] = _encode(_openapi_value.", field.name, "))")
    end
    if model.additional_type !== nothing
        println(io, "    for (_openapi_key, _openapi_item) in _openapi_value.additional_properties")
        println(io, "        haskey(_openapi_output, _openapi_key) && throw(ArgumentError(\"additional property conflicts with declared field: \" * _openapi_key))")
        println(io, "        _openapi_output[_openapi_key] = _encode(_openapi_item)")
        println(io, "    end")
    end
    println(io, "    return _validate_schema(", schema, ", _openapi_output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
    println(io, "end\n")
    println(io, "function _form_fields(_openapi_value::", model.name, ")")
    println(io, "    _openapi_output = Pair{String,Any}[]")
    for field in model.fields
        println(
            io,
            "    _openapi_value.",
            field.name,
            " isa Absent || push!(_openapi_output, ",
            repr(field.wire_name),
            " => _openapi_value.",
            field.name,
            ")",
        )
    end
    if model.additional_type !== nothing
        println(io, "    append!(_openapi_output, collect(_openapi_value.additional_properties))")
    end
    println(io, "    return _openapi_output")
    println(io, "end\n")
end

function _schema_node(handle::Union{Nothing,SchemaHandle})
    handle === nothing && return nothing
    compiled = handle.compiled
    return compiled === nothing ? handle.node : compiled.root
end

function _schema_descriptor(node::Union{Nothing,Resources.NodeId})
    node === nothing && return "nothing"
    return "(resource = " * repr(string(node.resource)) *
           ", pointer = " * repr(string(node.pointer)) * ")"
end

function _dialect_literal(value::SchemaEngine.Dialect)
    return "SchemaEngine.Dialect(" * join(
        (
            repr(value.name),
            repr(value.uri),
            repr(value.id_keyword),
            repr(value.ref_siblings),
            repr(value.modern_items),
            repr(value.unevaluated),
            repr(value.dynamic_refs),
            repr(value.recursive_refs),
            repr(value.applicator),
            repr(value.validation),
        ),
        ", ",
    ) * ")"
end

function _append_encoding_schema_handles!(handles, encodings)
    for encoding in encodings
        for header in encoding.headers
            header.schema === nothing || push!(handles, header.schema)
            for header_media in header.content
                header_media.schema === nothing || push!(handles, header_media.schema)
            end
        end
        _append_encoding_schema_handles!(handles, encoding.encoding)
    end
    return handles
end

function _source_schema_node(registry, node::Resources.NodeId)
    resource = Resources.resource(registry, node.resource)
    source = resource.source
    source_resource = Resources.resource(registry, source.resource)
    pointer = Resources.JSONPointer(
        (source.pointer.tokens..., node.pointer.tokens...),
    )
    return Resources.NodeId(source_resource.id, pointer)
end

function _directional_required_rules(plan::GenerationPlan, template)
    registry = template.registry
    directional_cache = Dict{Tuple{Resources.NodeId,String},Bool}()
    rules = Dict{
        Resources.NodeId,
        Tuple{Set{String},Set{String}},
    }()
    nodes = values(getfield(template, :evaluation_nodes))
    for node in nodes
        schema = node.value
        schema isa AbstractDict || continue
        required = get(schema, "required", nothing)
        required isa AbstractVector || continue
        view = SchemaView(
            schema,
            node.id,
            plan.api.source.version,
            template,
        )
        members, _ = _object_members(view)
        properties = Dict(member[1] => member[2] for member in members)
        input = Set{String}()
        output = Set{String}()
        for raw_name in required
            name = String(raw_name)
            property = get(properties, name, nothing)
            property === nothing && continue
            _has_directional_property(
                property,
                "readOnly",
                directional_cache,
            ) && push!(input, name)
            _has_directional_property(
                property,
                "writeOnly",
                directional_cache,
            ) && push!(output, name)
        end
        (isempty(input) && isempty(output)) && continue
        target = _source_schema_node(registry, node.id)
        existing = get!(rules, target) do
            (Set{String}(), Set{String}())
        end
        union!(existing[1], input)
        union!(existing[2], output)
    end
    output = collect(rules)
    sort!(
        output;
        by = entry -> (
            string(entry.first.resource),
            string(entry.first.pointer),
        ),
    )
    return output
end

function _client_schema_handles(plan::GenerationPlan)
    handles = SchemaHandle[last(pair) for pair in plan.api.schemas]
    for operation in plan.api.operations
        operation.direction === :request || continue
        for parameter in operation.parameters
            parameter.schema === nothing || push!(handles, parameter.schema)
            for media in parameter.content
                media.schema === nothing || push!(handles, media.schema)
            end
        end
        if operation.request_body !== nothing
            for media in operation.request_body.content
                media.schema === nothing || push!(handles, media.schema)
                _append_encoding_schema_handles!(handles, media.encoding)
            end
        end
        for response in operation.responses
            for media in response.content
                media.schema === nothing || push!(handles, media.schema)
            end
            for header in response.headers
                header.schema === nothing || push!(handles, header.schema)
                for media in header.content
                    media.schema === nothing || push!(handles, media.schema)
                end
            end
        end
    end
    unique!(handle -> handle.node, handles)
    sort!(
        handles;
        by = handle -> (string(handle.node.resource), string(handle.node.pointer)),
    )
    return handles
end

function _emit_schema_data(io::IO, plan::GenerationPlan)
    handles = _client_schema_handles(plan)
    graph = isempty(handles) ? nothing : first(handles).workspace.compiled
    if graph === nothing
        println(io, "const _SCHEMA_RESOURCE_DATA = Any[]")
        println(io, "const _SCHEMA_ROOT_DATA = Any[]")
        println(io, "const _SCHEMA_DIALECT_DATA = Any[]")
        println(io, "const _SCHEMA_DIRECTIONAL_REQUIRED = Any[]\n")
        return
    end
    template = getfield(graph, :template)
    registry = template.registry
    resources = Resources.Resource[
        resource for resource in values(getfield(registry, :resources))
        if isempty(resource.source.pointer)
    ]
    sort!(resources; by = resource -> string(resource.id))
    # Do not emit large metadata collections as tuples. A tuple literal encodes
    # every entry in its Julia type. Real descriptions can contain tens of
    # thousands of schema roots and directional rules, which makes top-level
    # type hashing and subtyping take minutes. An Any vector keeps stable values
    # without creating a giant tuple type.
    println(io, "const _SCHEMA_RESOURCE_DATA = Any[")
    for resource in resources
        println(
            io,
            "    (id = ",
            repr(string(resource.id)),
            ", retrieval = ",
            repr(string(resource.retrieval)),
            ", media_type = ",
            _julia_literal(resource.media_type),
            ", json = ",
            repr(JSON.json(resource.contents)),
            "),",
        )
    end
    println(io, "]")

    roots = Resources.NodeId[_schema_node(handle) for handle in handles]
    evaluation_nodes = getfield(template, :evaluation_nodes)
    for resource in resources
        root = Resources.NodeId(resource.id, Resources.JSONPointer())
        haskey(evaluation_nodes, root) && push!(roots, root)
    end
    unique!(roots)
    sort!(roots; by = node -> (string(node.resource), string(node.pointer)))
    println(io, "const _SCHEMA_ROOT_DATA = Any[")
    for root in roots
        node = get(evaluation_nodes, root, nothing)
        node === nothing && continue
        println(
            io,
            "    (resource = ",
            repr(string(root.resource)),
            ", pointer = ",
            repr(string(root.pointer)),
            ", dialect = ",
            _dialect_literal(node.dialect),
            "),",
        )
    end
    println(io, "]")
    println(io, "const _SCHEMA_DIALECT_DATA = Any[")
    aliases = collect(getfield(template, :dialect_aliases))
    sort!(aliases; by = first)
    for (uri, dialect) in aliases
        println(
            io,
            "    (uri = ",
            repr(uri),
            ", name = ",
            repr(dialect.name),
            ", id_keyword = ",
            repr(dialect.id_keyword),
            ", ref_siblings = ",
            repr(dialect.ref_siblings),
            ", modern_items = ",
            repr(dialect.modern_items),
            ", unevaluated = ",
            repr(dialect.unevaluated),
            ", dynamic_refs = ",
            repr(dialect.dynamic_refs),
            ", recursive_refs = ",
            repr(dialect.recursive_refs),
            ", applicator = ",
            repr(dialect.applicator),
            ", validation = ",
            repr(dialect.validation),
            "),",
        )
    end
    println(io, "]")
    println(io, "const _SCHEMA_DIRECTIONAL_REQUIRED = Any[")
    for (node, removals) in _directional_required_rules(plan, template)
        println(
            io,
            "    (resource = ",
            repr(string(node.resource)),
            ", pointer = ",
            repr(string(node.pointer)),
            ", input = ",
            _julia_literal(Tuple(sort!(collect(removals[1])))),
            ", output = ",
            _julia_literal(Tuple(sort!(collect(removals[2])))),
            "),",
        )
    end
    println(io, "]\n")
    return
end

function _parameter_descriptor(parameter::ParameterPlan)
    content = if isempty(parameter.parameter.content)
        "()"
    else
        media = Pair{String,String}[
            item.content_type => "Any" for item in parameter.parameter.content
        ]
        _media_descriptor(media, parameter.parameter.content)
    end
    return "(arg = " * repr(Symbol(parameter.name)) *
           ", name = " * repr(parameter.wire_name) *
           ", type = " * parameter.type *
           ", location = " * repr(parameter.location) *
           ", style = " * repr(something(parameter.style, :none)) *
           ", explode = " * (parameter.explode === true ? "true" : "false") *
           ", allow_reserved = " * (parameter.allow_reserved ? "true" : "false") *
           ", shape = " * repr(_schema_shape(_parameter_schema(parameter.parameter))) *
           ", schema = " *
           _schema_descriptor(_schema_node(_parameter_schema(parameter.parameter))) *
           ", content = " * content *
           ", required = " * (parameter.required ? "true" : "false") * ")"
end

function _named_encoding_properties(view::Union{Nothing,SchemaView})
    view === nothing && return Dict{String,SchemaView}()
    members, _ = _object_members(view)
    return Dict(member[1] => member[2] for member in members)
end

function _named_encoding_value_view(view::SchemaView)
    types = _without_null_type(_effective_types(view))
    if "array" in types || _keyword_owner(view, "items") !== nothing
        owner = _keyword_owner(view, "items")
        if owner !== nothing
            raw = owner.value["items"]
            (raw isa AbstractDict || raw isa Bool) && raw !== false &&
                return _child_view(owner, "items")
        end
    end
    return view
end

function _encoding_content_base(content_type)
    content_type === nothing && return ""
    selected = strip(first(split(String(content_type), ','; limit = 2)))
    return lowercase(strip(first(split(selected, ';'; limit = 2))))
end

function _field_wire_kind(view::SchemaView)
    format = _primitive_format(view)
    format in ("byte", "base64", "binary") && return :bytes
    _is_object_schema(view) && return :object
    types = unique(_without_null_type(_effective_types(view)))
    length(types) == 1 || return :default
    type = only(types)
    type in ("string", "boolean", "integer", "number") || return :default
    return Symbol(type)
end

function _encoding_descriptor(
    encoding::NormalizedEncoding,
    base_media_type::String,
    value_view::Union{Nothing,SchemaView},
)
    header_descriptors = String[]
    if startswith(base_media_type, "multipart/")
        for header in encoding.headers
            push!(header_descriptors, _header_descriptor(header, "Any"))
        end
    end
    encoded_headers = "(" * join(header_descriptors, ',') *
                      (length(header_descriptors) == 1 ? "," : "") * ")"

    nested_descriptors = String[]
    nested_properties = value_view === nothing ? Dict{String,SchemaView}() :
                        _named_encoding_properties(
        _named_encoding_value_view(value_view),
    )
    nested_base = _encoding_content_base(encoding.content_type)
    for nested in encoding.encoding
        nested_view = get(nested_properties, nested.name, nothing)
        nested_view === nothing && continue
        push!(
            nested_descriptors,
            _encoding_descriptor(nested, nested_base, nested_view),
        )
    end
    encoded_nested = "(" * join(nested_descriptors, ',') *
                     (length(nested_descriptors) == 1 ? "," : "") * ")"

    return "(" *
           "name = " * repr(encoding.name) *
           ", content_type = " * _julia_literal(encoding.content_type) *
           ", headers = " * encoded_headers *
           ", encoding = " * encoded_nested *
           ", style = " * _julia_literal(encoding.style) *
           ", explode = " * _julia_literal(encoding.explode) *
           ", allow_reserved = " * _julia_literal(encoding.allow_reserved) *
           ", rfc6570 = " * _julia_literal(
        base_media_type in (
            "application/x-www-form-urlencoded",
            "multipart/form-data",
        ) &&
        (
            encoding.style !== nothing ||
            encoding.explode !== nothing ||
            haskey(encoding.raw, "allowReserved")
        ),
    ) *
           ")"
end

function _media_descriptor(media, normalized)
    Base.@nospecialize media normalized
    items = String[]
    for (entry, source) in zip(media, normalized)
        base_media_type = lowercase(
            strip(first(split(String(entry.first), ';'; limit = 2))),
        )
        properties = source.schema === nothing ? Dict{String,SchemaView}() :
                     _named_encoding_properties(SchemaView(source.schema))
        encodings = String[]
        for encoding in source.encoding
            value_view = get(properties, encoding.name, nothing)
            value_view === nothing && continue
            push!(
                encodings,
                _encoding_descriptor(encoding, base_media_type, value_view),
            )
        end
        encoded = "(" * join(encodings, ',') *
                  (length(encodings) == 1 ? "," : "") * ")"
        # Form and multipart request decoding needs each top-level property's
        # shape so single-valued exploded arrays still decode as arrays.
        fields = "()"
        if base_media_type == "application/x-www-form-urlencoded" ||
           startswith(base_media_type, "multipart/")
            field_items = String[
                "(name = " * repr(field_name) *
                ", shape = " * repr(_schema_shape(field_view)) *
                ", kind = " * repr(_field_wire_kind(field_view)) *
                ", item_kind = " * repr(
                    _field_wire_kind(_named_encoding_value_view(field_view)),
                ) * ")" for
                (field_name, field_view) in sort(collect(properties); by = first)
            ]
            fields = "(" * join(field_items, ',') *
                     (length(field_items) == 1 ? "," : "") * ")"
        end
        push!(
            items,
            "(" * repr(entry.first) * ", " * entry.second * ", " *
            _schema_descriptor(_schema_node(source.schema)) * ", " * encoded *
            ", " * fields * ")",
        )
    end
    return "(" * join(items, ',') * (length(items) == 1 ? "," : "") * ")"
end

function _schema_shape(view::SchemaView)
    resolved = _resolved_view(view)
    _is_object_schema(resolved) && return :object
    types = _schema_types(resolved.value)
    (
        "array" in types ||
        resolved.value isa AbstractDict &&
        (haskey(resolved.value, "items") || haskey(resolved.value, "prefixItems"))
    ) &&
        return :array
    return :scalar
end

_schema_shape(handle::Union{Nothing,SchemaHandle}) =
    handle === nothing ? :scalar : _schema_shape(SchemaView(handle))

function _header_descriptor(header::NormalizedHeader, type::String)
    schema = header.schema !== nothing ? header.schema :
             isempty(header.content) ? nothing : first(header.content).schema
    content = isempty(header.content) ? "()" :
              _media_descriptor(
        Pair{String,String}[media.content_type => type for media in header.content],
        header.content,
    )
    return "(name = " * repr(header.name) *
           ", type = " * type *
           ", required = " * repr(header.required) *
           ", shape = " * repr(_schema_shape(schema)) *
           ", explode = " * repr(header.explode) *
           ", schema = " * _schema_descriptor(_schema_node(schema)) *
           ", content = " * content * ")"
end

function _security_descriptor(requirements)
    Base.@nospecialize requirements
    alternatives = String[]
    for requirement in requirements
        entries = String[
            "(" * repr(name) * ", " * _julia_literal(scopes) * ")" for
            (name, scopes) in requirement.alternatives
        ]
        push!(alternatives, "(" * join(entries, ',') * (length(entries) == 1 ? "," : "") * ")")
    end
    return "(" * join(alternatives, ',') * (length(alternatives) == 1 ? "," : "") * ")"
end

function _emit_operation_descriptor(io, operation::OperationPlan, api::NormalizedAPI)
    const_name = "_OP_" * operation.name
    println(io, "const ", const_name, " = (")
    println(io, "    id = ", repr(operation.operation.id), ",")
    println(io, "    method = ", repr(String(operation.operation.method)), ",")
    println(io, "    path = ", repr(operation.operation.path), ",")
    parameters = String[]
    for parameter in operation.parameters
        push!(parameters, _parameter_descriptor(parameter))
    end
    println(io, "    parameters = (", join(parameters, ','), length(parameters) == 1 ? "," : "", "),")
    if operation.request_body === nothing
        println(io, "    request = nothing,")
    else
        request = operation.request_body
        println(
            io,
            "    request = (required = ",
            request.required ? "true" : "false",
            ", media = ",
            _media_descriptor(request.media_types, request.body.content),
            "),",
        )
    end
    println(io, "    responses = (")
    for response in operation.responses
        headers = String[]
        for (header, type) in zip(
            response.response.headers,
            response.header_types,
        )
            push!(headers, _header_descriptor(header, type.second))
        end
        encoded_headers = "(" * join(headers, ',') *
                          (length(headers) == 1 ? "," : "") * ")"
        println(
            io,
            "        (selector = ",
            repr(response.selector),
            ", media = ",
            _media_descriptor(response.media_types, response.response.content),
            ", headers = ",
            encoded_headers,
            "),",
        )
    end
    println(io, "    ),")
    println(io, "    security = ", _security_descriptor(operation.operation.security), ",")
    println(
        io,
        "    servers = ",
        _server_descriptor(
            operation.operation.servers,
            api,
            operation.operation.provenance.node,
        ),
        ",",
    )
    println(io, ")\n")
    return const_name
end

function _ordered_path_parameters(operation::OperationPlan)
    byname = Dict{String,ParameterPlan}()
    for parameter in operation.parameters
        parameter.location === :path || continue
        byname[parameter.wire_name] = parameter
    end
    output = ParameterPlan[]
    seen = Set{String}()
    for match in eachmatch(r"\{([^{}]+)\}", operation.operation.path)
        name = String(match.captures[1])
        haskey(byname, name) && !(name in seen) || continue
        push!(seen, name)
        push!(output, byname[name])
    end
    return output
end

function _emit_operation(io, operation::OperationPlan, const_name)
    path_parameters = _ordered_path_parameters(operation)
    path_names = Set{String}()
    for parameter in path_parameters
        push!(path_names, parameter.name)
    end
    required_keywords = ParameterPlan[]
    optional_keywords = ParameterPlan[]
    for parameter in operation.parameters
        parameter.name in path_names && continue
        push!(
            parameter.required ? required_keywords : optional_keywords,
            parameter,
        )
    end
    positional = String[]
    for parameter in path_parameters
        push!(positional, string(parameter.name, "::", parameter.type))
    end
    if operation.request_body !== nothing && operation.request_body.required
        push!(positional, "body::" * operation.request_body.type)
    end
    keywords = String[]
    for parameter in required_keywords
        push!(keywords, parameter.name * "::" * parameter.type)
    end
    for parameter in optional_keywords
        push!(keywords, parameter.name * "::" * parameter.type * " = ABSENT")
    end
    if operation.request_body !== nothing && !operation.request_body.required
        push!(keywords, "body::" * operation.request_body.type * " = ABSENT")
    end
    has_multipart_request = operation.request_body !== nothing && any(
        media -> startswith(
            lowercase(strip(first(split(media.content_type, ';'; limit = 2)))),
            "multipart/",
        ),
        operation.request_body.body.content,
    )
    has_multipart_request && push!(keywords, "multipart_headers = NamedTuple()")
    append!(
        keywords,
        [
            "client::Client = DEFAULT_CLIENT",
            "content_type::Union{Nothing,AbstractString} = nothing",
            "accept::Union{Nothing,AbstractString} = nothing",
            "with_http_info::Bool = false",
            "request_headers = Pair{String,String}[]",
            "request_options::NamedTuple = NamedTuple()",
            "stream_to::Union{Nothing,Channel} = nothing",
        ],
    )
    summary = something(operation.operation.summary, operation.operation.description, "")
    doc = "    " * operation.name * "(...)\n"
    isempty(summary) || (doc *= "\n" * summary * "\n")
    doc *= "\n`" * String(operation.operation.method) * " " *
           operation.operation.path * "`"
    println(io, "@doc ", repr(doc))
    println(
        io,
        "function ",
        operation.name,
        "(",
        join(positional, ", "),
        "; ",
        join(keywords, ", "),
        ")",
    )
    println(io, "    _openapi_values = Dict{Symbol,Any}()")
    for parameter in operation.parameters
        println(io, "    _openapi_values[", repr(Symbol(parameter.name)), "] = ", parameter.name)
    end
    body_expression = operation.request_body === nothing ? "ABSENT" : "body"
    print(
        io,
        "    return _request(client, ",
        const_name,
        ", _openapi_values; body = ",
        body_expression,
        ", content_type, accept, with_http_info, request_headers, request_options, stream_to",
    )
    has_multipart_request && print(io, ", multipart_headers")
    println(io, ")")
    println(io, "end\n")
end

function _generate(plan::ClientPlan)
    io = IOBuffer()
    println(
        io,
        "# Generated by OpenAPI.jl from ",
        repr(plan.api.title),
        " version ",
        repr(plan.api.api_version),
        ". Do not edit.",
    )
    println(io, "module ", plan.module_name, "\n")
    println(io, "using HTTP, JSON, OpenAPI, Base64, Dates, UUIDs")
    plan.datetime === :zoned && println(io, "using TimeZones")
    println(io, "const SchemaEngine = OpenAPI.SchemaEngine\n")
    _emit_security(io, plan)
    _emit_schema_data(io, plan)
    default_server = _default_server(plan.api)
    print(io, GENERATED_RUNTIME_COMMON, '\n')
    plan.datetime === :zoned && print(io, GENERATED_ZONED_RUNTIME, '\n')
    print(io, GENERATED_RUNTIME, '\n')
    println(io, "const _DEFAULT_SERVER = ", repr(default_server))
    println(io, "const SERVER = Ref{String}(_DEFAULT_SERVER)")
    println(io, "const DEFAULT_CLIENT = Client()\n")

    indices = _model_indices(plan)
    wrapped_aliases = _cyclic_aliases(plan)
    abstract_targets = _forward_abstracts(plan, wrapped_aliases)
    for target in sort(collect(abstract_targets))
        println(io, "abstract type Abstract", target, " end")
    end
    isempty(abstract_targets) || println(io)
    for (index, model) in enumerate(plan.models)
        _emit_model(
            io,
            model,
            index,
            indices,
            abstract_targets,
            wrapped_aliases,
        )
    end
    for operation in plan.operations
        const_name = _emit_operation_descriptor(io, operation, plan.api)
        _emit_operation(io, operation, const_name)
    end
    println(io, "end # module ", plan.module_name)
    return String(take!(io))
end

"""
    OpenAPI.client(source; name="ApiClient", path=nothing, strict=true, options...) -> String

Generate a deterministic Julia client module after full OpenAPI loading,
reference binding, semantic normalization, and type planning. The generated
module supports OpenAPI 3.0, 3.1, and 3.2 request/response models, parameter
styles, content negotiation, and security requirements.

`datetime = :utc` (the default) maps `format: date-time` to `Dates.DateTime`
and normalizes RFC 3339 offsets to UTC while decoding; `datetime = :zoned`
maps to `TimeZones.ZonedDateTime` and preserves offsets, making the generated
module depend on TimeZones.jl.
"""
function client(
    source;
    name::AbstractString = "ApiClient",
    path::Union{Nothing,AbstractString} = nothing,
    strict::Bool = true,
    kwargs...,
)
    client_plan = source isa ClientPlan ? source : plan(source; name, strict, kwargs...)
    output = _generate(client_plan)
    if path !== nothing
        open(path, "w") do io
            write(io, output)
        end
    end
    return output
end
