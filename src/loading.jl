"""
    DocumentVersion(value::AbstractString)

The parsed `openapi` version declaration of a source document. Accepts 3.0.x,
3.1.x, and 3.2.x values, with an optional prerelease suffix, and rejects
everything else. Carries `raw`, `major`, `minor`, `patch`, and `prerelease`
fields; [`OpenAPI.oas_family`](@ref) names the minor line it belongs to.
"""
struct DocumentVersion
    raw::String
    major::Int
    minor::Int
    patch::Int
    prerelease::Union{Nothing,String}
end

function DocumentVersion(value::AbstractString)
    matched = match(r"^(3)\.(0|1|2)\.([0-9]+)(?:-([0-9A-Za-z.-]+))?$", value)
    matched === nothing && throw(
        ArgumentError(
            "unsupported OpenAPI version $(repr(value)); expected 3.0.x, 3.1.x, or 3.2.x",
        ),
    )
    return DocumentVersion(
        String(value),
        Base.parse(Int, matched.captures[1]),
        Base.parse(Int, matched.captures[2]),
        Base.parse(Int, matched.captures[3]),
        matched.captures[4] === nothing ? nothing : String(matched.captures[4]),
    )
end

"""
    oas_family(version::DocumentVersion) -> Symbol

The OAS minor line a document belongs to: `:oas30`, `:oas31`, or `:oas32`.
Behavior that differs between specification lines — structural schema
selection, normalization rules — follows this family, never the patch version.
"""
oas_family(version::DocumentVersion) = Symbol("oas3", version.minor)

"""An immutable, parsed OpenAPI source resource."""
struct SourceDocument
    resource::Resources.Resource
    version::DocumentVersion
    format::Symbol
    locations::Dict{Resources.JSONPointer,SourcePosition}
end

function Base.getproperty(document::SourceDocument, name::Symbol)
    name === :locations && return copy(getfield(document, :locations))
    return getfield(document, name)
end

Base.getindex(document::SourceDocument, key) = document.resource.contents[key]
Base.haskey(document::SourceDocument, key) = haskey(document.resource.contents, key)
Base.keys(document::SourceDocument) = keys(document.resource.contents)

"""
    location(document::SourceDocument, pointer = Resources.JSONPointer()) -> SourceLocation

The source location of the value at `pointer` inside a loaded document. When
no position was recorded for the exact node, the nearest recorded ancestor's
position is reported. Diagnostics use these locations to point back into the
original JSON or YAML text.
"""
function location(
    document::SourceDocument,
    pointer::Resources.JSONPointer = Resources.JSONPointer(),
)
    locations = getfield(document, :locations)
    current = pointer
    position = nothing
    while true
        position = get(locations, current, nothing)
        position === nothing || break
        isempty(current) && break
        current = Resources.JSONPointer(current.tokens[1:(end - 1)])
    end
    return SourceLocation(document.resource.id, pointer; position)
end

const SPEC_SCHEMA_LOCK = ReentrantLock()
const SPEC_SCHEMA_CACHE = Dict{Int,Any}()

function _schema_path(minor::Int)
    return normpath(@__DIR__, "..", "schemas", "oas-3.$minor.json")
end

function _spec_schema(minor::Int)
    return lock(SPEC_SCHEMA_LOCK) do
        return get!(SPEC_SCHEMA_CACHE, minor) do
            return SchemaEngine.CompiledSchema(JSON.parsefile(_schema_path(minor)))
        end
    end
end

function _file_id(path::AbstractString)
    absolute = abspath(expanduser(path))
    uri = Resources.URIs.URI(; scheme = "file", path = absolute)
    return Resources.ResourceId(uri)
end

function _inline_id(base_uri)
    base_uri === nothing && return Resources.ResourceId("urn:openapi:inline")
    return base_uri isa Resources.ResourceId ? base_uri : Resources.ResourceId(base_uri)
end

function _format_from_hint(hint::AbstractString)
    lowered = lowercase(hint)
    if endswith(lowered, ".json") ||
       occursin("application/json", lowered) ||
       occursin("+json", lowered)
        return :json
    elseif endswith(lowered, ".yaml") ||
           endswith(lowered, ".yml") ||
           occursin("yaml", lowered)
        return :yaml
    end
    return :auto
end

function _sniff_format(bytes::AbstractVector{UInt8}, hint::Symbol)
    hint in (:json, :yaml) && return hint
    text = lstrip(String(copy(bytes)))
    (startswith(text, "{") || startswith(text, "[")) && return :json
    return :yaml
end

function _source_bytes(
    source::AbstractString,
    bag::DiagnosticBag;
    base_uri = nothing,
    format::Symbol = :auto,
    max_bytes::Integer = 16 * 1024 * 1024,
)
    max_bytes > 0 || throw(ArgumentError("max_bytes must be positive"))
    format in (:auto, :json, :yaml) ||
        throw(ArgumentError("format must be :auto, :json, or :yaml"))
    stripped = strip(source)
    bytes = UInt8[]
    retrieval = _inline_id(base_uri)
    hint = format
    if startswith(stripped, "http://") || startswith(stripped, "https://")
        Base.get_extension(@__MODULE__, :OpenAPIHTTPExt) === nothing && throw(
            ArgumentError("reading an OpenAPI document from a URL requires `using HTTP`"),
        )
        requested = Resources.ResourceId(stripped)
        fetched = fetchresource(requested, max_bytes)
        bytes = getfield(fetched, :bytes)
        retrieval = fetched.id
        hint === :auto &&
            (hint = _format_from_hint(something(fetched.media_type, stripped)))
    elseif _isfile(stripped)
        file_size = filesize(stripped)
        file_size <= max_bytes ||
            throw(ArgumentError("OpenAPI source exceeds the $max_bytes-byte input limit"))
        bytes = Base.read(stripped)
        retrieval = _file_id(stripped)
        hint === :auto && (hint = _format_from_hint(stripped))
    else
        bytes = Vector{UInt8}(codeunits(source))
    end
    length(bytes) <= max_bytes ||
        throw(ArgumentError("OpenAPI source exceeds the $max_bytes-byte input limit"))
    isempty(bytes) && throw(ArgumentError("OpenAPI source is empty"))
    return bytes, retrieval, _sniff_format(bytes, hint)
end

function _isfile(source::AbstractString)
    (startswith(source, '{') || startswith(source, '[')) && return false
    (occursin('\n', source) || occursin('\r', source) || occursin('\0', source)) &&
        return false
    return try
        isfile(source)
    catch error
        error isa IOError || error isa SystemError || rethrow()
        false
    end
end

function _yaml_mapping(constructor, node)
    return YAML.construct_mapping(
        JSON.Object{String,Any},
        constructor,
        node;
        strict_unique_keys = true,
    )
end

function _yaml_string(constructor, node)
    return string(YAML.construct_scalar(constructor, node))
end

function _parse_yaml(text::AbstractString)
    constructors = Dict{String,Function}(
        "tag:yaml.org,2002:map" => _yaml_mapping,
        "tag:yaml.org,2002:timestamp" => _yaml_string,
    )
    return YAML.load(text, constructors)
end

function _normalize_value(
    value,
    pointer::Resources.JSONPointer,
    active::IdDict{Any,Nothing},
    count::Base.RefValue{Int},
    max_nodes::Int,
    max_depth::Int,
    depth::Int = 0,
)
    depth <= max_depth || throw(ArgumentError("OpenAPI source exceeds the depth limit"))
    count[] += 1
    count[] <= max_nodes || throw(ArgumentError("OpenAPI source exceeds the node limit"))
    if value isa AbstractDict || value isa AbstractVector
        haskey(active, value) &&
            throw(ArgumentError("OpenAPI source contains an alias cycle"))
        active[value] = nothing
    end
    try
        if value isa AbstractDict
            normalized = JSON.Object{String,Any}()
            sizehint!(normalized, length(value))
            for (key, child) in value
                key isa AbstractString || throw(
                    ArgumentError(
                        "OpenAPI object key at $(string(pointer)) is not a string",
                    ),
                )
                name = String(key)
                normalized[name] = _normalize_value(
                    child,
                    pointer / name,
                    active,
                    count,
                    max_nodes,
                    max_depth,
                    depth + 1,
                )
            end
            return normalized
        elseif value isa AbstractVector
            normalized = Any[]
            sizehint!(normalized, length(value))
            for (index, child) in enumerate(value)
                push!(
                    normalized,
                    _normalize_value(
                        child,
                        pointer / string(index - 1),
                        active,
                        count,
                        max_nodes,
                        max_depth,
                        depth + 1,
                    ),
                )
            end
            return normalized
        elseif value === nothing ||
               value isa Bool ||
               value isa Integer ||
               value isa AbstractString
            return value
        elseif value isa AbstractFloat
            isfinite(value) || throw(
                ArgumentError(
                    "OpenAPI source contains a non-finite number at $(string(pointer))",
                ),
            )
            return value
        end
        throw(
            ArgumentError(
                "OpenAPI source contains non-JSON value $(typeof(value)) at $(string(pointer))",
            ),
        )
    finally
        (value isa AbstractDict || value isa AbstractVector) && delete!(active, value)
    end
end

function _parse_source(
    bytes::AbstractVector{UInt8},
    format::Symbol;
    max_nodes::Integer,
    max_depth::Integer,
    source_locations::Bool = false,
)
    max_nodes > 0 || throw(ArgumentError("max_nodes must be positive"))
    max_depth > 0 || throw(ArgumentError("max_depth must be positive"))
    text = String(copy(bytes))
    parsed = if format === :json
        JSON.parse(text; duplicate_keys = :error)
    elseif format === :yaml
        _parse_yaml(text)
    else
        throw(ArgumentError("format must be :auto, :json, or :yaml"))
    end
    normalized = _normalize_value(
        parsed,
        Resources.JSONPointer(),
        IdDict{Any,Nothing}(),
        Ref(0),
        Int(max_nodes),
        Int(max_depth),
    )
    source_locations || return normalized
    locations = format === :json ? _json_locations(bytes, Int(max_depth)) :
                _yaml_locations(text)
    return normalized, locations
end

function _document_version(root, retrieval, bag::DiagnosticBag)
    root isa AbstractDict || begin
        location = SourceLocation(retrieval)
        _error!(bag, :root_type, "the OpenAPI document root must be an object", location)
        _throw_on_errors("Cannot load OpenAPI document", bag.diagnostics)
    end
    declared = get(root, "openapi", nothing)
    declared isa AbstractString || begin
        location = SourceLocation(retrieval, Resources.JSONPointer("/openapi"))
        _error!(
            bag,
            :missing_version,
            "required field `openapi` is missing or is not a string",
            location,
        )
        _throw_on_errors("Cannot load OpenAPI document", bag.diagnostics)
    end
    try
        return DocumentVersion(declared)
    catch error
        location = SourceLocation(retrieval, Resources.JSONPointer("/openapi"))
        _error!(bag, :unsupported_version, sprint(showerror, error), location)
        _throw_on_errors("Cannot load OpenAPI document", bag.diagnostics)
    end
end

function _canonical_document_id(root, retrieval, version, bag)
    version.minor == 2 || return retrieval
    self = get(root, "\$self", nothing)
    self === nothing && return retrieval
    self isa AbstractString || begin
        _error!(
            bag,
            :invalid_self,
            "`\$self` must be a URI-reference string",
            SourceLocation(retrieval, Resources.JSONPointer("/\$self")),
        )
        return retrieval
    end
    try
        return Resources.Reference(retrieval, self).resource
    catch error
        _error!(
            bag,
            :invalid_self,
            sprint(showerror, error),
            SourceLocation(retrieval, Resources.JSONPointer("/\$self")),
        )
        return retrieval
    end
end

function _load_document(
    source::AbstractString,
    bag::DiagnosticBag;
    base_uri = nothing,
    format::Symbol = :auto,
    max_bytes::Integer = 16 * 1024 * 1024,
    max_nodes::Integer = 1_000_000,
    max_depth::Integer = 512,
)
    bytes, retrieval, detected = _source_bytes(source, bag; base_uri, format, max_bytes)
    root, locations = try
        _parse_source(
            bytes,
            detected;
            max_nodes,
            max_depth,
            source_locations = true,
        )
    catch error
        _error!(
            bag,
            :parse_error,
            sprint(showerror, error),
            SourceLocation(
                retrieval;
                position = _parse_error_position(error, bytes),
            ),
        )
        _throw_on_errors("Cannot parse OpenAPI document", bag.diagnostics)
    end
    version = _document_version(root, retrieval, bag)
    canonical = _canonical_document_id(root, retrieval, version, bag)
    resource = Resources.Resource(
        canonical,
        root;
        retrieval,
        media_type = detected === :json ? "application/openapi+json" :
                     "application/openapi+yaml",
    )
    return SourceDocument(
        resource,
        version,
        detected,
        locations,
    )
end

function _load_document(
    source::AbstractDict,
    bag::DiagnosticBag;
    base_uri = nothing,
    max_nodes::Integer = 1_000_000,
    max_depth::Integer = 512,
    kwargs...,
)
    retrieval = _inline_id(base_uri)
    root = _normalize_value(
        source,
        Resources.JSONPointer(),
        IdDict{Any,Nothing}(),
        Ref(0),
        Int(max_nodes),
        Int(max_depth),
    )
    version = _document_version(root, retrieval, bag)
    canonical = _canonical_document_id(root, retrieval, version, bag)
    resource = Resources.Resource(canonical, root; retrieval)
    return SourceDocument(
        resource,
        version,
        :memory,
        Dict{Resources.JSONPointer,SourcePosition}(),
    )
end

_load_document(source::SourceDocument, bag::DiagnosticBag; kwargs...) = source

function _structural_diagnostics!(bag::DiagnosticBag, document::SourceDocument)
    schema = _spec_schema(document.version.minor)
    issues = try
        SchemaEngine.validate(
            schema,
            document.resource.contents;
            fail_fast = false,
            max_issues = bag.max_diagnostics,
        )
    catch error
        _error!(bag, :validation_failure, sprint(showerror, error), location(document))
        return bag
    end
    for issue in issues
        pointer = try
            Resources.JSONPointer(issue.path)
        catch
            Resources.JSONPointer()
        end
        message = "fails the `$(issue.reason)` constraint"
        _error!(bag, :spec_schema, message, location(document, pointer))
    end
    return bag
end

"""
    OpenAPI.load(source; options...) -> SourceDocument

Parse JSON or YAML, enforce resource limits, detect OAS 3.0/3.1/3.2, and run
the official structural schema for that OAS minor line.
"""
function load(source; max_diagnostics::Integer = 1_000, validate::Bool = true, kwargs...)
    bag = DiagnosticBag(max_diagnostics)
    document = _load_document(source, bag; kwargs...)
    validate && _structural_diagnostics!(bag, document)
    _throw_on_errors("Invalid OpenAPI document", bag.diagnostics)
    return document
end

"""Return all structural diagnostics without throwing for validation errors."""
function check(source; max_diagnostics::Integer = 1_000, kwargs...)
    bag = DiagnosticBag(max_diagnostics)
    try
        document = _load_document(source, bag; kwargs...)
        _structural_diagnostics!(bag, document)
    catch error
        error isa OpenAPIError || rethrow()
        isempty(bag.diagnostics) && append!(bag.diagnostics, error.diagnostics)
    end
    return copy(bag.diagnostics)
end
