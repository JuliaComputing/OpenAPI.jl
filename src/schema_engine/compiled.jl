# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

struct CompilationError <: Exception
    location::Resources.NodeId
    reason::String
end

function Base.showerror(io::IO, err::CompilationError)
    pointer = string(err.location.pointer)
    location =
        string(err.location.resource) * (isempty(pointer) ? "" : "#" * pointer)
    return print(
        io,
        "cannot compile JSON Schema at ",
        repr(location),
        ": ",
        err.reason,
    )
end

struct PendingReference
    base::Resources.ResourceId
    keyword::String
    reference::String
    dialect::Dialect
    location::Resources.NodeId
end

struct CompiledNode
    index::Int
    id::Resources.NodeId
    value::Union{Resources.FrozenObject,Bool}
    dialect::Dialect
end

mutable struct Compiler{R<:Resources.AbstractRetriever}
    registry::Resources.Registry
    dialects::Dict{Resources.NodeId,Dialect}
    dialect_aliases::Dict{String,Dialect}
    recursive_anchors::Set{Resources.ResourceId}
    references::Dict{Tuple{Resources.NodeId,String},Resources.NodeId}
    regexes::Dict{String,Regex}
    evaluation_nodes::Dict{Resources.NodeId,CompiledNode}
    transitions::Dict{Tuple{Int,Tuple{Vararg{String}}},CompiledNode}
    uses_annotations::Bool
    retriever::R
    pending::Vector{PendingReference}
    loaded::Set{Resources.ResourceId}
    loading::Set{Resources.ResourceId}
    max_resources::Int
    max_nodes::Int
    max_depth::Int
    nodes::Int
    values::Int
end

function Compiler(
    retriever::R,
    max_resources::Integer,
    max_nodes::Integer,
    max_depth::Integer,
) where {R<:Resources.AbstractRetriever}
    max_resources > 0 || throw(ArgumentError("max_resources must be positive"))
    max_nodes > 0 || throw(ArgumentError("max_nodes must be positive"))
    max_depth > 0 || throw(ArgumentError("max_depth must be positive"))
    return Compiler(
        Resources.Registry(),
        Dict{Resources.NodeId,Dialect}(),
        Dict{String,Dialect}(),
        Set{Resources.ResourceId}(),
        Dict{Tuple{Resources.NodeId,String},Resources.NodeId}(),
        Dict{String,Regex}(),
        Dict{Resources.NodeId,CompiledNode}(),
        Dict{Tuple{Int,Tuple{Vararg{String}}},CompiledNode}(),
        false,
        retriever,
        PendingReference[],
        Set{Resources.ResourceId}(),
        Set{Resources.ResourceId}(),
        Int(max_resources),
        Int(max_nodes),
        Int(max_depth),
        0,
        0,
    )
end

function _register_dialect_aliases!(compiler::Compiler, aliases::AbstractDict)
    for (uri, target) in aliases
        uri isa AbstractString ||
            throw(ArgumentError("dialect alias identifiers must be strings"))
        compiler.dialect_aliases[_normalized_dialect_uri(uri)] = dialect(target)
    end
    return compiler
end

"""A non-mutating, dialect-aware JSON Schema resource graph."""
struct CompiledSchema{R<:Resources.AbstractRetriever}
    data::Union{Resources.FrozenObject,Bool}
    dialect::Dialect
    registry::Resources.FrozenRegistry
    root::Resources.NodeId
    dialects::Dict{Resources.NodeId,Dialect}
    dialect_aliases::Dict{String,Dialect}
    evaluation_nodes::Dict{Resources.NodeId,CompiledNode}
    transitions::Dict{Tuple{Int,Tuple{Vararg{String}}},CompiledNode}
    uses_annotations::Bool
    recursive_anchors::Set{Resources.ResourceId}
    references::Dict{Tuple{Resources.NodeId,String},Resources.NodeId}
    regexes::Dict{String,Regex}
    retriever::R
end

"""A compiled graph with multiple JSON Schema roots embedded in JSON resources."""
struct CompiledSchemas{R<:Resources.AbstractRetriever}
    template::CompiledSchema{R}
    roots::Dict{Resources.NodeId,Resources.NodeId}

    function CompiledSchemas(template::CompiledSchema{R}, roots) where {R}
        return new{R}(template, copy(roots))
    end
end

function Base.getproperty(schemas::CompiledSchemas, name::Symbol)
    name === :roots && return copy(getfield(schemas, :roots))
    return getfield(schemas, name)
end

function Base.getproperty(schema::CompiledSchema, name::Symbol)
    name in (
        :dialects,
        :dialect_aliases,
        :evaluation_nodes,
        :transitions,
        :references,
        :regexes,
    ) && return copy(getfield(schema, name))
    name === :recursive_anchors && return copy(getfield(schema, name))
    return getfield(schema, name)
end

"""
    reference_target(schema, source[, keyword="\$ref"])

Return the canonical target node bound to a reference keyword at `source`.
Return `nothing` when the compiled graph has no such binding. This lookup does
not copy the graph's reference table.
"""
function reference_target(
    schema::CompiledSchema,
    source::Resources.NodeId,
    keyword::AbstractString = "\$ref",
)
    canonical = Resources.canonical(schema.registry, source)
    return get(
        getfield(schema, :references),
        (canonical, String(keyword)),
        nothing,
    )
end

function reference_target(
    schemas::CompiledSchemas,
    source::Resources.NodeId,
    keyword::AbstractString = "\$ref",
)
    return reference_target(getfield(schemas, :template), source, keyword)
end

function _directory_resource(parent_dir::AbstractString)
    path = abspath(expanduser(parent_dir))
    endswith(path, Base.Filesystem.path_separator) ||
        (path *= Base.Filesystem.path_separator)
    return Resources.ResourceId(URIs.URI(; scheme = "file", path))
end

function _resource_id(base_uri, parent_dir)
    if base_uri !== nothing
        return base_uri isa Resources.ResourceId ? base_uri :
               Resources.ResourceId(base_uri)
    end
    parent_dir === nothing &&
        return Resources.ResourceId("urn:jsonschema:anonymous")
    return _directory_resource(parent_dir)
end

function _source_child(source::Resources.NodeId, tokens)
    pointer = source.pointer
    for token in tokens
        pointer = pointer / string(token)
    end
    return Resources.NodeId(source.resource, pointer)
end

function _check_source!(
    value,
    count::Base.RefValue{Int},
    active::IdDict{Any,Nothing},
    max_nodes::Int,
    max_depth::Int,
    depth::Int = 0,
)
    depth <= max_depth || throw(
        ArgumentError("the JSON value exceeds the depth limit of $max_depth"),
    )
    count[] += 1
    count[] <= max_nodes ||
        throw(ArgumentError("the JSON value exceeds the $max_nodes-node limit"))
    (value isa AbstractDict || value isa AbstractVector) || return
    haskey(active, value) &&
        throw(ArgumentError("the JSON value contains a reference cycle"))
    active[value] = nothing
    try
        if value isa AbstractDict
            for (key, child) in value
                key isa AbstractString ||
                    throw(ArgumentError("JSON object keys must be strings"))
                _check_source!(
                    child,
                    count,
                    active,
                    max_nodes,
                    max_depth,
                    depth + 1,
                )
            end
        else
            for child in value
                _check_source!(
                    child,
                    count,
                    active,
                    max_nodes,
                    max_depth,
                    depth + 1,
                )
            end
        end
    finally
        delete!(active, value)
    end
    return
end

function _check_source!(compiler::Compiler, value)
    count = Ref(compiler.values)
    _check_source!(
        value,
        count,
        IdDict{Any,Nothing}(),
        compiler.max_nodes,
        compiler.max_depth,
    )
    compiler.values = count[]
    return
end

function _node_child(node::Resources.NodeId, tokens)
    pointer = node.pointer
    for token in tokens
        pointer = pointer / string(token)
    end
    return Resources.NodeId(node.resource, pointer)
end

function _anchor_name(fragment::Resources.Fragment)
    fragment isa Resources.RootFragment && return nothing
    fragment isa Resources.AnchorFragment && return fragment.name
    return throw(
        ArgumentError("an identifier cannot use a JSON Pointer fragment"),
    )
end

function _declared_identifier(schema::AbstractDict, schema_dialect::Dialect)
    identifier = get(schema, schema_dialect.id_keyword, nothing)
    identifier === nothing && return nothing
    identifier isa AbstractString || return throw(
        ArgumentError("$(schema_dialect.id_keyword) must be a string"),
    )
    return String(identifier)
end

_declared_identifier(::Bool, ::Dialect) = nothing

function _root_identity(
    schema,
    retrieval::Resources.ResourceId,
    schema_dialect::Dialect,
)
    if schema isa AbstractDict &&
       !schema_dialect.ref_siblings &&
       haskey(schema, "\$ref")
        return (retrieval, nothing)
    end
    identifier = _declared_identifier(schema, schema_dialect)
    identifier === nothing && return (retrieval, nothing)
    reference = Resources.Reference(retrieval, identifier)
    anchor = _anchor_name(reference.fragment)
    if anchor !== nothing && schema_dialect.name in (:draft201909, :draft202012)
        throw(
            ArgumentError(
                "$(schema_dialect.id_keyword) cannot contain a non-empty fragment",
            ),
        )
    end
    return (reference.resource, anchor)
end

const CORE_VOCABULARIES = Set([
    "https://json-schema.org/draft/2019-09/vocab/core",
    "https://json-schema.org/draft/2020-12/vocab/core",
])
const APPLICATOR_VOCABULARIES = Set([
    "https://json-schema.org/draft/2019-09/vocab/applicator",
    "https://json-schema.org/draft/2020-12/vocab/applicator",
])
const VALIDATION_VOCABULARIES = Set([
    "https://json-schema.org/draft/2019-09/vocab/validation",
    "https://json-schema.org/draft/2020-12/vocab/validation",
])
const UNEVALUATED_VOCABULARIES =
    Set(["https://json-schema.org/draft/2020-12/vocab/unevaluated"])
const SUPPORTED_VOCABULARIES = union(
    CORE_VOCABULARIES,
    APPLICATOR_VOCABULARIES,
    VALIDATION_VOCABULARIES,
    UNEVALUATED_VOCABULARIES,
    Set([
        "https://json-schema.org/draft/2019-09/vocab/meta-data",
        "https://json-schema.org/draft/2019-09/vocab/format",
        "https://json-schema.org/draft/2019-09/vocab/content",
        "https://json-schema.org/draft/2020-12/vocab/meta-data",
        "https://json-schema.org/draft/2020-12/vocab/format-annotation",
        "https://json-schema.org/draft/2020-12/vocab/content",
    ]),
)

function _custom_dialect!(
    compiler::Compiler,
    uri::AbstractString,
    default::Dialect,
)
    normalized = _normalized_dialect_uri(uri)
    cached = get(compiler.dialect_aliases, normalized, nothing)
    cached === nothing || return cached
    id = Resources.ResourceId(normalized)
    retrieved = Resources.retrieve(compiler.retriever, id)
    meta = try
        JSON.parse(String(copy(retrieved.bytes)))
    catch err
        throw(UnsupportedDialectError("$uri ($(sprint(showerror, err)))"))
    end
    base = dialect(meta; default)
    vocabularies = get(meta, "\$vocabulary", nothing)
    applicator = base.applicator
    validation = base.validation
    unevaluated = base.unevaluated
    if vocabularies isa AbstractDict
        for (vocabulary, required) in vocabularies
            vocabulary isa AbstractString || throw(
                UnsupportedDialectError(
                    "$uri has a non-string vocabulary identifier",
                ),
            )
            required isa Bool || throw(
                UnsupportedDialectError(
                    "$uri has a non-boolean vocabulary requirement",
                ),
            )
            if required && !(String(vocabulary) in SUPPORTED_VOCABULARIES)
                throw(
                    UnsupportedDialectError(
                        "$uri requires unknown vocabulary $vocabulary",
                    ),
                )
            end
        end
        any(
            vocabulary -> String(vocabulary) in CORE_VOCABULARIES,
            keys(vocabularies),
        ) || throw(
            UnsupportedDialectError(
                "$uri does not declare the core vocabulary",
            ),
        )
        all(
            vocabulary -> vocabularies[vocabulary] === true,
            filter(
                vocabulary -> String(vocabulary) in CORE_VOCABULARIES,
                collect(keys(vocabularies)),
            ),
        ) || throw(
            UnsupportedDialectError(
                "$uri declares the core vocabulary as optional",
            ),
        )
        applicator = any(
            vocabulary -> String(vocabulary) in APPLICATOR_VOCABULARIES,
            keys(vocabularies),
        )
        validation = any(
            vocabulary -> String(vocabulary) in VALIDATION_VOCABULARIES,
            keys(vocabularies),
        )
        unevaluated = if base.name == :draft201909
            applicator
        else
            any(
                vocabulary ->
                    String(vocabulary) in UNEVALUATED_VOCABULARIES,
                keys(vocabularies),
            )
        end
    end
    custom = Dialect(;
        name = base.name,
        uri = normalized,
        id_keyword = base.id_keyword,
        ref_siblings = base.ref_siblings,
        modern_items = base.modern_items,
        unevaluated,
        dynamic_refs = base.dynamic_refs,
        recursive_refs = base.recursive_refs,
        applicator,
        validation,
    )
    compiler.dialect_aliases[normalized] = custom
    return custom
end

function _schema_dialect!(
    compiler::Compiler,
    schema,
    default::Dialect,
    resource_root::Bool,
)
    resource_root || return default
    schema isa AbstractDict || return default
    declared = get(schema, "\$schema", nothing)
    declared === nothing && return default
    declared isa AbstractString ||
        throw(UnsupportedDialectError(repr(declared)))
    try
        return dialect(declared)
    catch err
        err isa UnsupportedDialectError || rethrow()
        return _custom_dialect!(compiler, declared, default)
    end
end

function _scan_dialect!(
    compiler::Compiler,
    schema,
    default::Dialect,
    resource_root::Bool,
)
    resource_root && return _schema_dialect!(compiler, schema, default, true)
    schema isa AbstractDict || return default
    haskey(schema, "\$schema") || return default
    candidate = _schema_dialect!(compiler, schema, default, true)
    return _declared_identifier(schema, candidate) === nothing ? default :
           candidate
end

function _schema_map_children!(children, schema, keyword::String)
    value = get(schema, keyword, nothing)
    value isa AbstractDict || return
    for (name, child) in value
        (child isa AbstractDict || child isa Bool) || continue
        push!(children, ((keyword, String(name)), child))
    end
    return
end

function _schema_array_children!(children, schema, keyword::String)
    value = get(schema, keyword, nothing)
    value isa AbstractVector || return
    for (index, child) in enumerate(value)
        (child isa AbstractDict || child isa Bool) || continue
        push!(children, ((keyword, string(index - 1)), child))
    end
    return
end

function _schema_child!(children, schema, keyword::String)
    value = get(schema, keyword, nothing)
    (value isa AbstractDict || value isa Bool) || return
    push!(children, ((keyword,), value))
    return
end

function _schema_children(schema::AbstractDict, schema_dialect::Dialect)
    children = Tuple{Tuple,Any}[]
    for keyword in ("properties", "patternProperties")
        keyword_applies(schema_dialect, keyword) &&
            _schema_map_children!(children, schema, keyword)
    end
    definitions =
        schema_dialect.name in (:draft4, :draft6, :draft7) ? "definitions" :
        "\$defs"
    keyword_applies(schema_dialect, definitions) &&
        _schema_map_children!(children, schema, definitions)
    keyword_applies(schema_dialect, "dependentSchemas") &&
        _schema_map_children!(children, schema, "dependentSchemas")
    for keyword in ("allOf", "anyOf", "oneOf")
        keyword_applies(schema_dialect, keyword) &&
            _schema_array_children!(children, schema, keyword)
    end
    keyword_applies(schema_dialect, "prefixItems") &&
        _schema_array_children!(children, schema, "prefixItems")
    for keyword in ("not", "additionalProperties")
        keyword_applies(schema_dialect, keyword) &&
            _schema_child!(children, schema, keyword)
    end
    keyword_applies(schema_dialect, "additionalItems") &&
        _schema_child!(children, schema, "additionalItems")
    if keyword_applies(schema_dialect, "contains")
        _schema_child!(children, schema, "contains")
    end
    if keyword_applies(schema_dialect, "propertyNames")
        _schema_child!(children, schema, "propertyNames")
    end
    if keyword_applies(schema_dialect, "if")
        for keyword in ("if", "then", "else")
            _schema_child!(children, schema, keyword)
        end
    end
    for keyword in
        ("unevaluatedItems", "unevaluatedProperties", "contentSchema")
        if keyword_applies(schema_dialect, keyword)
            _schema_child!(children, schema, keyword)
        end
    end
    items = get(schema, "items", nothing)
    if items isa AbstractVector &&
       keyword_applies(schema_dialect, "items") &&
       !schema_dialect.modern_items
        for (index, child) in enumerate(items)
            (child isa AbstractDict || child isa Bool) || continue
            push!(children, (("items", string(index - 1)), child))
        end
    elseif keyword_applies(schema_dialect, "items") &&
           (items isa AbstractDict || items isa Bool)
        push!(children, (("items",), items))
    end
    dependencies = get(schema, "dependencies", nothing)
    if dependencies isa AbstractDict &&
       keyword_applies(schema_dialect, "dependencies")
        for (name, child) in dependencies
            (child isa AbstractDict || child isa Bool) || continue
            push!(children, (("dependencies", String(name)), child))
        end
    end
    return children
end

_schema_children(::Bool, ::Dialect) = Tuple{Tuple,Any}[]

function _register_anchor!(
    compiler::Compiler,
    node::Resources.NodeId,
    name,
    keyword::String;
    dialect::Dialect,
    dynamic::Bool = false,
)
    name === nothing && return
    name isa AbstractString ||
        throw(CompilationError(node, "$keyword must be a string"))
    pattern =
        dialect.name == :draft202012 ? r"^[A-Za-z_][-A-Za-z0-9._]*$" :
        r"^[A-Za-z][-A-Za-z0-9._:]*$"
    occursin(pattern, name) ||
        throw(CompilationError(node, "$keyword has an invalid anchor name"))
    try
        Resources.register_anchor!(
            compiler.registry,
            node.resource,
            name,
            node.pointer;
            dynamic,
        )
    catch err
        err isa CompilationError && rethrow()
        throw(CompilationError(node, sprint(showerror, err)))
    end
    return
end

function _record_references!(compiler::Compiler, schema, node, schema_dialect)
    schema isa AbstractDict || return
    keywords =
        schema_dialect.name == :draft202012 ? ("\$ref", "\$dynamicRef") :
        schema_dialect.name == :draft201909 ? ("\$ref", "\$recursiveRef") :
        ("\$ref",)
    for keyword in keywords
        reference = get(schema, keyword, nothing)
        reference === nothing && continue
        reference isa AbstractString ||
            throw(CompilationError(node, "$keyword must be a string"))
        push!(
            compiler.pending,
            PendingReference(
                node.resource,
                keyword,
                String(reference),
                schema_dialect,
                node,
            ),
        )
    end
    return
end

function _register_nested_resource!(
    compiler::Compiler,
    schema,
    raw_node::Resources.NodeId,
    source::Resources.NodeId,
    schema_dialect::Dialect,
    identifier::String,
)
    reference = Resources.Reference(raw_node.resource, identifier)
    anchor = _anchor_name(reference.fragment)
    if anchor !== nothing && schema_dialect.name in (:draft201909, :draft202012)
        throw(
            CompilationError(
                raw_node,
                "$(schema_dialect.id_keyword) cannot contain a non-empty fragment",
            ),
        )
    end
    if reference.resource == raw_node.resource && anchor !== nothing
        _register_anchor!(
            compiler,
            raw_node,
            anchor,
            schema_dialect.id_keyword;
            dialect = schema_dialect,
        )
        return (raw_node, false)
    end
    if reference.resource == raw_node.resource &&
       anchor === nothing &&
       isempty(raw_node.pointer)
        return (raw_node, true)
    end
    registered = Resources.resource(compiler.registry, raw_node.resource)
    nested = Resources.Resource(
        reference.resource,
        schema;
        retrieval = registered.retrieval,
        source,
        media_type = registered.media_type,
    )
    try
        length(compiler.registry.resources) < compiler.max_resources || throw(
            Resources.RetrievalError(
                reference.resource,
                "the resource limit was reached",
            ),
        )
        Resources.register!(compiler.registry, nested; alias_retrieval = false)
        Resources.register_boundary!(
            compiler.registry,
            raw_node,
            Resources.NodeId(reference.resource, Resources.JSONPointer()),
        )
    catch err
        throw(CompilationError(raw_node, sprint(showerror, err)))
    end
    node = Resources.NodeId(reference.resource, Resources.JSONPointer())
    anchor === nothing || _register_anchor!(
        compiler,
        node,
        anchor,
        schema_dialect.id_keyword;
        dialect = schema_dialect,
    )
    return (node, true)
end

_is_schema_value(value) = value isa AbstractDict || value isa Bool
_is_json_number(value) = value isa Real && !(value isa Bool) && isfinite(value)
function _is_nonnegative_integer(value)
    return _is_json_number(value) && isinteger(value) && value >= 0
end

function _compile_regex!(
    compiler::Compiler,
    node::Resources.NodeId,
    pattern::AbstractString,
)
    normalized = String(pattern)
    haskey(compiler.regexes, normalized) && return compiler.regexes[normalized]
    regex = try
        _ecma_regex(normalized)
    catch err
        throw(
            CompilationError(
                node,
                "invalid ECMA-262 regular expression: $(sprint(showerror, err))",
            ),
        )
    end
    compiler.regexes[normalized] = regex
    return regex
end

function _require_schema(node, keyword, value)
    _is_schema_value(value) || throw(
        CompilationError(
            node,
            "$keyword must contain an object or boolean schema",
        ),
    )
    return
end

function _require_schema_map(node, keyword, value)
    value isa AbstractDict ||
        throw(CompilationError(node, "$keyword must be an object"))
    for (name, child) in value
        name isa AbstractString ||
            throw(CompilationError(node, "$keyword keys must be strings"))
        _require_schema(node, "$keyword[$(repr(name))]", child)
    end
    return
end

function _require_schema_array(node, keyword, value)
    value isa AbstractVector ||
        throw(CompilationError(node, "$keyword must be an array"))
    isempty(value) &&
        throw(CompilationError(node, "$keyword must not be empty"))
    for child in value
        _require_schema(node, keyword, child)
    end
    return
end

function _require_string_array(node, keyword, value; nonempty::Bool = false)
    value isa AbstractVector ||
        throw(CompilationError(node, "$keyword must be an array"))
    nonempty &&
        isempty(value) &&
        throw(CompilationError(node, "$keyword must not be empty"))
    all(item -> item isa AbstractString, value) ||
        throw(CompilationError(node, "$keyword entries must be strings"))
    length(Set(String.(value))) == length(value) ||
        throw(CompilationError(node, "$keyword entries must be unique"))
    return
end

function _validate_schema_keywords!(
    compiler::Compiler,
    schema::Bool,
    node::Resources.NodeId,
    schema_dialect::Dialect,
)
    return
end

function _validate_schema_keywords!(
    compiler::Compiler,
    schema::AbstractDict,
    node::Resources.NodeId,
    schema_dialect::Dialect,
)
    for keyword in ("\$ref", "\$dynamicRef", "\$recursiveRef")
        keyword_applies(schema_dialect, keyword) || continue
        haskey(schema, keyword) || continue
        schema[keyword] isa AbstractString ||
            throw(CompilationError(node, "$keyword must be a string"))
    end
    for keyword in (
        "properties",
        "patternProperties",
        "definitions",
        "\$defs",
        "dependentSchemas",
    )
        keyword_applies(schema_dialect, keyword) || continue
        haskey(schema, keyword) || continue
        _require_schema_map(node, keyword, schema[keyword])
    end
    patterns = get(schema, "patternProperties", nothing)
    if keyword_applies(schema_dialect, "patternProperties") &&
       patterns isa AbstractDict
        for pattern in keys(patterns)
            _compile_regex!(compiler, node, String(pattern))
        end
    end
    for keyword in ("allOf", "anyOf", "oneOf", "prefixItems")
        keyword_applies(schema_dialect, keyword) || continue
        haskey(schema, keyword) || continue
        _require_schema_array(node, keyword, schema[keyword])
    end
    for keyword in (
        "not",
        "additionalProperties",
        "additionalItems",
        "contains",
        "propertyNames",
        "if",
        "then",
        "else",
        "unevaluatedItems",
        "unevaluatedProperties",
        "contentSchema",
    )
        keyword_applies(schema_dialect, keyword) || continue
        haskey(schema, keyword) || continue
        _require_schema(node, keyword, schema[keyword])
    end
    if keyword_applies(schema_dialect, "items") && haskey(schema, "items")
        items = schema["items"]
        if schema_dialect.modern_items
            _require_schema(node, "items", items)
        elseif items isa AbstractVector
            isempty(items) ||
                foreach(child -> _require_schema(node, "items", child), items)
        else
            _require_schema(node, "items", items)
        end
    end
    if keyword_applies(schema_dialect, "dependencies") &&
       haskey(schema, "dependencies")
        dependencies = schema["dependencies"]
        dependencies isa AbstractDict ||
            throw(CompilationError(node, "dependencies must be an object"))
        for value in values(dependencies)
            if value isa AbstractVector
                _require_string_array(node, "dependencies", value)
            else
                _require_schema(node, "dependencies", value)
            end
        end
    end
    if keyword_applies(schema_dialect, "dependentRequired") &&
       haskey(schema, "dependentRequired")
        dependencies = schema["dependentRequired"]
        dependencies isa AbstractDict ||
            throw(CompilationError(node, "dependentRequired must be an object"))
        for value in values(dependencies)
            _require_string_array(node, "dependentRequired", value)
        end
    end
    if keyword_applies(schema_dialect, "type") && haskey(schema, "type")
        types = schema["type"]
        allowed = Set([
            "null",
            "boolean",
            "object",
            "array",
            "number",
            "string",
            "integer",
        ])
        if types isa AbstractString
            String(types) in allowed ||
                throw(CompilationError(node, "type is not a JSON type"))
        else
            _require_string_array(node, "type", types; nonempty = true)
            all(type -> String(type) in allowed, types) || throw(
                CompilationError(node, "type contains an unknown JSON type"),
            )
        end
    end
    if keyword_applies(schema_dialect, "enum") && haskey(schema, "enum")
        enum = schema["enum"]
        enum isa AbstractVector ||
            throw(CompilationError(node, "enum must be an array"))
    end
    if haskey(schema, "multipleOf") &&
       keyword_applies(schema_dialect, "multipleOf")
        multiple = schema["multipleOf"]
        _is_json_number(multiple) && multiple > 0 || throw(
            CompilationError(node, "multipleOf must be a positive number"),
        )
    end
    for keyword in ("maximum", "minimum")
        haskey(schema, keyword) && keyword_applies(schema_dialect, keyword) ||
            continue
        _is_json_number(schema[keyword]) ||
            throw(CompilationError(node, "$keyword must be a number"))
    end
    for keyword in ("exclusiveMaximum", "exclusiveMinimum")
        haskey(schema, keyword) && keyword_applies(schema_dialect, keyword) ||
            continue
        valid =
            schema_dialect.name == :draft4 ? schema[keyword] isa Bool :
            _is_json_number(schema[keyword])
        valid || throw(
            CompilationError(
                node,
                "$keyword has the wrong type for the dialect",
            ),
        )
    end
    for keyword in (
        "maxLength",
        "minLength",
        "maxItems",
        "minItems",
        "maxProperties",
        "minProperties",
        "minContains",
        "maxContains",
    )
        haskey(schema, keyword) && keyword_applies(schema_dialect, keyword) ||
            continue
        _is_nonnegative_integer(schema[keyword]) || throw(
            CompilationError(node, "$keyword must be a non-negative integer"),
        )
    end
    if haskey(schema, "uniqueItems") &&
       keyword_applies(schema_dialect, "uniqueItems")
        schema["uniqueItems"] isa Bool ||
            throw(CompilationError(node, "uniqueItems must be a boolean"))
    end
    if haskey(schema, "required") && keyword_applies(schema_dialect, "required")
        _require_string_array(node, "required", schema["required"])
    end
    if haskey(schema, "pattern") && keyword_applies(schema_dialect, "pattern")
        pattern = schema["pattern"]
        pattern isa AbstractString ||
            throw(CompilationError(node, "pattern must be a string"))
        _compile_regex!(compiler, node, pattern)
    end
    return
end

function _scan!(
    compiler::Compiler,
    schema,
    node::Resources.NodeId,
    source::Resources.NodeId,
    default_dialect::Dialect;
    resource_root::Bool = false,
    identifier_applied::Bool = false,
    depth::Int = 0,
)
    requested = node
    node = Resources.canonical(compiler.registry, node)
    if haskey(compiler.dialects, node)
        compiler.evaluation_nodes[requested] = compiler.evaluation_nodes[node]
        return node
    end
    depth <= compiler.max_depth || throw(
        CompilationError(
            node,
            "the schema exceeds the depth limit of $(compiler.max_depth)",
        ),
    )
    compiler.nodes += 1
    compiler.nodes <= compiler.max_nodes || throw(
        CompilationError(
            node,
            "the schema exceeds the $(compiler.max_nodes)-node limit",
        ),
    )
    schema_dialect = try
        _scan_dialect!(compiler, schema, default_dialect, resource_root)
    catch err
        throw(CompilationError(node, sprint(showerror, err)))
    end
    current = node
    became_root = resource_root
    reference_only =
        schema isa AbstractDict &&
        !schema_dialect.ref_siblings &&
        haskey(schema, "\$ref")
    if !identifier_applied && !reference_only
        identifier = try
            _declared_identifier(schema, schema_dialect)
        catch err
            throw(CompilationError(node, sprint(showerror, err)))
        end
        if identifier !== nothing
            current, became_root = _register_nested_resource!(
                compiler,
                schema,
                node,
                source,
                schema_dialect,
                identifier,
            )
            if became_root
                schema_dialect = try
                    _schema_dialect!(compiler, schema, schema_dialect, true)
                catch err
                    throw(CompilationError(current, sprint(showerror, err)))
                end
            end
        end
    end
    compiled_node =
        CompiledNode(compiler.nodes, current, schema, schema_dialect)
    if schema isa AbstractDict && schema_dialect.unevaluated
        compiler.uses_annotations |=
            haskey(schema, "unevaluatedItems") ||
            haskey(schema, "unevaluatedProperties")
    end
    compiler.evaluation_nodes[requested] = compiled_node
    compiler.evaluation_nodes[node] = compiled_node
    compiler.evaluation_nodes[current] = compiled_node
    compiler.dialects[current] = schema_dialect
    if reference_only
        _record_references!(compiler, schema, current, schema_dialect)
        return current
    end
    _validate_schema_keywords!(compiler, schema, current, schema_dialect)
    if schema isa AbstractDict
        if schema_dialect.name in (:draft201909, :draft202012)
            _register_anchor!(
                compiler,
                current,
                get(schema, "\$anchor", nothing),
                "\$anchor";
                dialect = schema_dialect,
            )
        end
        if schema_dialect.dynamic_refs
            _register_anchor!(
                compiler,
                current,
                get(schema, "\$dynamicAnchor", nothing),
                "\$dynamicAnchor";
                dialect = schema_dialect,
                dynamic = true,
            )
        end
        if schema_dialect.recursive_refs
            recursive = get(schema, "\$recursiveAnchor", false)
            recursive === true &&
                push!(compiler.recursive_anchors, current.resource)
            (recursive isa Bool) || throw(
                CompilationError(
                    current,
                    "\$recursiveAnchor must be a boolean",
                ),
            )
        end
    end
    _record_references!(compiler, schema, current, schema_dialect)
    for (tokens, child) in _schema_children(schema, schema_dialect)
        child_node = _node_child(current, tokens)
        child_source = _source_child(source, tokens)
        child_current = _scan!(
            compiler,
            child,
            child_node,
            child_source,
            schema_dialect;
            depth = depth + 1,
        )
        transition = (compiled_node.index, tokens)
        compiler.transitions[transition] =
            compiler.evaluation_nodes[child_current]
    end
    return current
end

function _compile_resource!(
    compiler::Compiler,
    schema,
    retrieval::Resources.ResourceId,
    default_dialect::Dialect;
    media_type = nothing,
)
    try
        _check_source!(compiler, schema)
    catch err
        location = Resources.NodeId(retrieval, Resources.JSONPointer())
        throw(CompilationError(location, sprint(showerror, err)))
    end
    frozen = Resources.freeze(schema)
    schema_dialect = try
        _schema_dialect!(compiler, frozen, default_dialect, true)
    catch err
        location = Resources.NodeId(retrieval, Resources.JSONPointer())
        throw(CompilationError(location, sprint(showerror, err)))
    end
    canonical, anchor = try
        _root_identity(frozen, retrieval, schema_dialect)
    catch err
        location = Resources.NodeId(retrieval, Resources.JSONPointer())
        throw(CompilationError(location, sprint(showerror, err)))
    end
    source = Resources.NodeId(retrieval, Resources.JSONPointer())
    resource =
        Resources.Resource(canonical, frozen; retrieval, source, media_type)
    try
        Resources.register!(compiler.registry, resource)
    catch err
        throw(CompilationError(source, sprint(showerror, err)))
    end
    push!(compiler.loaded, retrieval)
    push!(compiler.loaded, canonical)
    root = Resources.NodeId(canonical, Resources.JSONPointer())
    anchor === nothing || _register_anchor!(
        compiler,
        root,
        anchor,
        schema_dialect.id_keyword;
        dialect = schema_dialect,
    )
    _scan!(
        compiler,
        frozen,
        root,
        source,
        schema_dialect;
        resource_root = true,
        identifier_applied = true,
    )
    return (root, frozen, schema_dialect)
end

function _load_reference!(
    compiler::Compiler,
    target::Resources.ResourceId,
    inherited::Dialect,
)
    haskey(compiler.registry, target) && return
    target in compiler.loading && return
    length(compiler.registry.resources) < compiler.max_resources || throw(
        Resources.RetrievalError(target, "the resource limit was reached"),
    )
    push!(compiler.loading, target)
    retrieved = try
        Resources.retrieve(compiler.retriever, target)
    catch
        delete!(compiler.loading, target)
        rethrow()
    end
    parsed = try
        JSON.parse(String(copy(retrieved.bytes)))
    catch err
        delete!(compiler.loading, target)
        throw(
            Resources.RetrievalError(
                target,
                "invalid JSON: $(sprint(showerror, err))",
            ),
        )
    end
    try
        root, _, _ = _compile_resource!(
            compiler,
            parsed,
            retrieved.id,
            inherited;
            media_type = retrieved.media_type,
        )
        if target != retrieved.id && !haskey(compiler.registry, target)
            Resources.register_alias!(compiler.registry, target, root.resource)
        end
    finally
        delete!(compiler.loading, target)
    end
    return
end

function _source_node(registry::Resources.AbstractRegistry, node::Resources.NodeId)
    registered = Resources.resource(registry, node.resource)
    pointer = registered.source.pointer
    for token in node.pointer
        pointer /= token
    end
    return Resources.NodeId(registered.source.resource, pointer)
end

function _resolve_pending!(compiler::Compiler)
    index = 1
    while index <= length(compiler.pending)
        pending = compiler.pending[index]
        reference = Resources.Reference(pending.base, pending.reference)
        if !haskey(compiler.registry, reference.resource)
            try
                _load_reference!(compiler, reference.resource, pending.dialect)
            catch err
                throw(
                    CompilationError(pending.location, sprint(showerror, err)),
                )
            end
        end
        resolved = try
            Resources.resolve(compiler.registry, reference)
        catch err
            throw(CompilationError(pending.location, sprint(showerror, err)))
        end
        (resolved.value isa AbstractDict || resolved.value isa Bool) || throw(
            CompilationError(
                pending.location,
                "$(pending.keyword) does not resolve to an object or boolean schema",
            ),
        )
        target = Resources.canonical(compiler.registry, resolved.id)
        if !haskey(compiler.dialects, target)
            target = _scan!(
                compiler,
                resolved.value,
                target,
                _source_node(compiler.registry, target),
                pending.dialect,
            )
        end
        target = Resources.canonical(compiler.registry, target)
        compiler.references[(pending.location, pending.keyword)] = target
        index += 1
    end
    return
end

function CompiledSchema(
    schema::Union{AbstractDict,Bool};
    dialect::Union{Dialect,Symbol,AbstractString} = DRAFT7,
    base_uri = nothing,
    parent_dir::Union{Nothing,AbstractString} = nothing,
    dialect_aliases::AbstractDict = Dict{String,Dialect}(),
    retriever::Resources.AbstractRetriever = Resources.DisabledRetriever(),
    max_resources::Integer = 256,
    max_nodes::Integer = 1_000_000,
    max_depth::Integer = 512,
)
    default_dialect = SchemaEngine.dialect(dialect)
    retrieval = _resource_id(base_uri, parent_dir)
    compiler = Compiler(retriever, max_resources, max_nodes, max_depth)
    _register_dialect_aliases!(compiler, dialect_aliases)
    root, frozen, schema_dialect =
        _compile_resource!(compiler, schema, retrieval, default_dialect)
    _resolve_pending!(compiler)
    return CompiledSchema(
        frozen,
        schema_dialect,
        Resources.freeze(compiler.registry),
        root,
        copy(compiler.dialects),
        copy(compiler.dialect_aliases),
        copy(compiler.evaluation_nodes),
        copy(compiler.transitions),
        compiler.uses_annotations,
        copy(compiler.recursive_anchors),
        copy(compiler.references),
        copy(compiler.regexes),
        retriever,
    )
end

function _compiled_schema(compiler::Compiler, root::Resources.NodeId)
    canonical = Resources.canonical(compiler.registry, root)
    resource = Resources.resource(compiler.registry, canonical.resource)
    data = Resources.resolve(resource.contents, canonical.pointer)
    schema_dialect = get(compiler.dialects, canonical, DRAFT7)
    return CompiledSchema(
        data,
        schema_dialect,
        Resources.freeze(compiler.registry),
        canonical,
        copy(compiler.dialects),
        copy(compiler.dialect_aliases),
        copy(compiler.evaluation_nodes),
        copy(compiler.transitions),
        compiler.uses_annotations,
        copy(compiler.recursive_anchors),
        copy(compiler.references),
        copy(compiler.regexes),
        compiler.retriever,
    )
end

function _root_dialect!(compiler::Compiler, value, fallback::Dialect)
    value isa Dialect && return value
    try
        return dialect(value)
    catch error
        error isa UnsupportedDialectError || rethrow()
        value isa AbstractString || rethrow()
        return _custom_dialect!(compiler, value, fallback)
    end
end

"""
    CompiledSchemas(resources, roots; options...)

Compile several JSON Schema roots embedded in one or more registered JSON
resources. `roots` contains `Resources.NodeId` values. All roots are scanned
before references are resolved, so a reference can target a sibling schema by
its `\$id` or anchor without retrieving another document. `root_dialects` can
map each requested or canonical root to a `Dialect`, registered dialect symbol,
or dialect URI. Roots not in the map use `dialect`. `dialect_aliases` maps
application dialect URI strings to compatible built-in dialects without
retrieving a meta-schema.
"""
function CompiledSchemas(
    resources::AbstractVector{<:Resources.Resource},
    roots::AbstractVector{<:Resources.NodeId};
    dialect::Union{Dialect,Symbol,AbstractString} = DRAFT7,
    root_dialects::AbstractDict = Dict{Resources.NodeId,Dialect}(),
    dialect_aliases::AbstractDict = Dict{String,Dialect}(),
    retriever::Resources.AbstractRetriever = Resources.DisabledRetriever(),
    max_resources::Integer = 256,
    max_nodes::Integer = 1_000_000,
    max_depth::Integer = 512,
)
    isempty(resources) &&
        throw(ArgumentError("at least one resource is required"))
    isempty(roots) &&
        throw(ArgumentError("at least one schema root is required"))
    length(resources) <= max_resources ||
        throw(ArgumentError("initial resources exceed max_resources"))
    default_dialect = SchemaEngine.dialect(dialect)
    compiler = Compiler(retriever, max_resources, max_nodes, max_depth)
    _register_dialect_aliases!(compiler, dialect_aliases)
    for resource in resources
        try
            _check_source!(compiler, resource.contents)
            Resources.register!(compiler.registry, resource)
            push!(compiler.loaded, resource.id)
            push!(compiler.loaded, resource.retrieval)
        catch error
            throw(CompilationError(resource.source, sprint(showerror, error)))
        end
    end
    compiled_roots = Dict{Resources.NodeId,Resources.NodeId}()
    for requested in roots
        registered = try
            Resources.resource(compiler.registry, requested.resource)
        catch error
            throw(CompilationError(requested, sprint(showerror, error)))
        end
        raw = Resources.NodeId(registered.id, requested.pointer)
        value = try
            Resources.resolve(registered.contents, requested.pointer)
        catch error
            throw(CompilationError(raw, sprint(showerror, error)))
        end
        (value isa AbstractDict || value isa Bool) || throw(
            CompilationError(
                raw,
                "the selected value is not an object or boolean schema",
            ),
        )
        selected_dialect = get(
            root_dialects,
            requested,
            get(root_dialects, raw, default_dialect),
        )
        schema_dialect = try
            _root_dialect!(compiler, selected_dialect, default_dialect)
        catch error
            throw(CompilationError(raw, sprint(showerror, error)))
        end
        root = _scan!(
            compiler,
            value,
            raw,
            _source_node(compiler.registry, raw),
            schema_dialect;
            resource_root = true,
        )
        compiled_roots[requested] = root
        compiled_roots[raw] = root
    end
    _resolve_pending!(compiler)
    for (requested, root) in collect(compiled_roots)
        compiled_roots[requested] = Resources.canonical(compiler.registry, root)
    end
    template = _compiled_schema(compiler, first(values(compiled_roots)))
    return CompiledSchemas(template, compiled_roots)
end

function CompiledSchemas(
    resource::Resources.Resource,
    pointers::AbstractVector{<:Resources.JSONPointer};
    kwargs...,
)
    roots = Resources.NodeId[
        Resources.NodeId(resource.id, pointer) for pointer in pointers
    ]
    return CompiledSchemas([resource], roots; kwargs...)
end

function select(schemas::CompiledSchemas, requested::Resources.NodeId)
    template = getfield(schemas, :template)
    roots = getfield(schemas, :roots)
    root = get(roots, requested, nothing)
    if root === nothing
        canonical = Resources.canonical(template.registry, requested)
        root = get(roots, canonical, nothing)
    end
    root === nothing &&
        throw(ArgumentError("the requested node is not a compiled schema root"))
    resource = Resources.resource(template.registry, root.resource)
    data = Resources.resolve(resource.contents, root.pointer)
    schema_dialect = get(getfield(template, :dialects), root, template.dialect)
    return CompiledSchema(
        data,
        schema_dialect,
        template.registry,
        root,
        getfield(template, :dialects),
        getfield(template, :dialect_aliases),
        getfield(template, :evaluation_nodes),
        getfield(template, :transitions),
        template.uses_annotations,
        getfield(template, :recursive_anchors),
        getfield(template, :references),
        getfield(template, :regexes),
        template.retriever,
    )
end

function select(
    schemas::CompiledSchemas,
    resource::Resources.ResourceId,
    pointer::Resources.JSONPointer = Resources.JSONPointer(),
)
    return select(schemas, Resources.NodeId(resource, pointer))
end

"""Return a compiled view of any schema node scanned in a schema graph."""
function subschema(schemas::CompiledSchemas, requested::Resources.NodeId)
    template = getfield(schemas, :template)
    return subschema(template, requested)
end

"""Return a compiled view of any schema node scanned in a compiled graph."""
function subschema(template::CompiledSchema, requested::Resources.NodeId)
    canonical = Resources.canonical(template.registry, requested)
    node = get(getfield(template, :evaluation_nodes), canonical, nothing)
    node === nothing && throw(
        ArgumentError("the requested node is not a compiled schema location"),
    )
    root = node.id
    resource = Resources.resource(template.registry, root.resource)
    data = Resources.resolve(resource.contents, root.pointer)
    schema_dialect = get(getfield(template, :dialects), root, template.dialect)
    return CompiledSchema(
        data,
        schema_dialect,
        template.registry,
        root,
        getfield(template, :dialects),
        getfield(template, :dialect_aliases),
        getfield(template, :evaluation_nodes),
        getfield(template, :transitions),
        template.uses_annotations,
        getfield(template, :recursive_anchors),
        getfield(template, :references),
        getfield(template, :regexes),
        template.retriever,
    )
end

function subschema(
    schemas::CompiledSchemas,
    resource::Resources.ResourceId,
    pointer::Resources.JSONPointer = Resources.JSONPointer(),
)
    return subschema(schemas, Resources.NodeId(resource, pointer))
end

function CompiledSchema(
    resource::Resources.Resource,
    pointer::Resources.JSONPointer = Resources.JSONPointer();
    dialect::Union{Dialect,Symbol,AbstractString} = DRAFT7,
    dialect_aliases::AbstractDict = Dict{String,Dialect}(),
    retriever::Resources.AbstractRetriever = Resources.DisabledRetriever(),
    max_resources::Integer = 256,
    max_nodes::Integer = 1_000_000,
    max_depth::Integer = 512,
)
    default_dialect = SchemaEngine.dialect(dialect)
    compiler = Compiler(retriever, max_resources, max_nodes, max_depth)
    _register_dialect_aliases!(compiler, dialect_aliases)
    try
        _check_source!(compiler, resource.contents)
        Resources.register!(compiler.registry, resource)
    catch err
        location = Resources.NodeId(resource.id, pointer)
        throw(CompilationError(location, sprint(showerror, err)))
    end
    raw_root = Resources.NodeId(resource.id, pointer)
    data = try
        Resources.resolve(resource.contents, pointer)
    catch err
        throw(CompilationError(raw_root, sprint(showerror, err)))
    end
    (data isa AbstractDict || data isa Bool) || throw(
        CompilationError(
            raw_root,
            "the selected value is not an object or boolean schema",
        ),
    )
    document_root = Resources.NodeId(resource.id, Resources.JSONPointer())
    if resource.contents isa AbstractDict || resource.contents isa Bool
        _scan!(
            compiler,
            resource.contents,
            document_root,
            _source_node(compiler.registry, document_root),
            default_dialect;
            resource_root = true,
        )
    end
    selected = get(compiler.evaluation_nodes, raw_root, nothing)
    root = if selected === nothing
        _scan!(
            compiler,
            data,
            raw_root,
            _source_node(compiler.registry, raw_root),
            default_dialect;
            resource_root = true,
        )
    else
        selected.id
    end
    _resolve_pending!(compiler)
    root = Resources.canonical(compiler.registry, root)
    schema_dialect = get(compiler.dialects, root, default_dialect)
    return CompiledSchema(
        data,
        schema_dialect,
        Resources.freeze(compiler.registry),
        root,
        copy(compiler.dialects),
        copy(compiler.dialect_aliases),
        copy(compiler.evaluation_nodes),
        copy(compiler.transitions),
        compiler.uses_annotations,
        copy(compiler.recursive_anchors),
        copy(compiler.references),
        copy(compiler.regexes),
        retriever,
    )
end

function CompiledSchema(schema::AbstractString; kwargs...)
    return CompiledSchema(JSON.parse(schema); kwargs...)
end

spec(schema::CompiledSchema) = schema.data
Base.getindex(schema::CompiledSchema, key) = schema.data[key]
Base.haskey(schema::CompiledSchema, key) = haskey(schema.data, key)
Base.get(schema::CompiledSchema, key, default) = get(schema.data, key, default)
Base.keys(schema::CompiledSchema) = keys(schema.data)
JSON.lower(schema::CompiledSchema) = schema.data

function Base.show(io::IO, schema::CompiledSchema)
    return print(io, "A compiled JSONSchema ($(schema.dialect.name))")
end
