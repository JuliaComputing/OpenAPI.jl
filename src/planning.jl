struct ModelFieldPlan
    name::String
    wire_name::String
    type::String
    required::Bool
    nullable::Bool
    default::Union{Nothing,String}
end

struct ModelPlan
    name::String
    kind::Symbol
    fields::Tuple{Vararg{ModelFieldPlan}}
    values::Tuple
    alias::Union{Nothing,String}
    additional_type::Union{Nothing,String}
    discriminator::Union{Nothing,String}
    discriminator_mapping::Tuple{
        Vararg{Pair{String,Pair{Resources.NodeId,String}}}
    }
    discriminator_default::Union{Nothing,Pair{Resources.NodeId,String}}
    variants::Tuple{Vararg{Pair{Resources.NodeId,String}}}
    direction::Symbol
    provenance::Provenance
end

struct ParameterPlan
    name::String
    wire_name::String
    location::Symbol
    type::String
    required::Bool
    style::Union{Nothing,Symbol}
    explode::Union{Nothing,Bool}
    allow_reserved::Bool
    parameter::NormalizedParameter
end

struct RequestBodyPlan
    name::String
    type::String
    required::Bool
    media_types::Tuple{Vararg{Pair{String,String}}}
    body::NormalizedRequestBody
end

struct ResponsePlan
    selector::String
    media_types::Tuple{Vararg{Pair{String,String}}}
    header_types::Tuple{Vararg{Pair{String,String}}}
    response::NormalizedResponse
end

struct OperationPlan
    name::String
    operation::NormalizedOperation
    parameters::Tuple{Vararg{ParameterPlan}}
    request_body::Union{Nothing,RequestBodyPlan}
    responses::Tuple{Vararg{ResponsePlan}}
    return_type::String
end

struct ClientPlan
    api::NormalizedAPI
    module_name::String
    models::Tuple{Vararg{ModelPlan}}
    operations::Tuple{Vararg{OperationPlan}}
    diagnostics::Tuple{Vararg{Diagnostic}}
    uses_dates::Bool
    uses_uuids::Bool
    uses_base64::Bool
    datetime::Symbol
end

struct ServerPlan
    api::NormalizedAPI
    module_name::String
    models::Tuple{Vararg{ModelPlan}}
    operations::Tuple{Vararg{OperationPlan}}
    diagnostics::Tuple{Vararg{Diagnostic}}
    uses_dates::Bool
    uses_uuids::Bool
    uses_base64::Bool
    datetime::Symbol
end

const GenerationPlan = Union{ClientPlan,ServerPlan}

struct SchemaView
    value::Any
    node::Resources.NodeId
    version::DocumentVersion
    compiled::Any
end

function SchemaView(handle::SchemaHandle)
    compiled = handle.compiled
    compiled === nothing &&
        return SchemaView(handle.value, handle.node, handle.version, nothing)
    node = compiled.root
    resource = Resources.resource(compiled.registry, node.resource)
    value = Resources.resolve(resource.contents, node.pointer)
    return SchemaView(value, node, handle.version, compiled)
end

mutable struct PlanningContext
    api::NormalizedAPI
    bag::DiagnosticBag
    names::Dict{Tuple{Resources.NodeId,Symbol},String}
    base_names::Dict{Resources.NodeId,String}
    used_names::Dict{String,Int}
    planned::Set{Tuple{Resources.NodeId,Symbol}}
    planning::Set{Tuple{Resources.NodeId,Symbol}}
    directional::Dict{Tuple{Resources.NodeId,String},Bool}
    nullable::Dict{Resources.NodeId,Bool}
    models::Vector{ModelPlan}
    uses_dates::Bool
    uses_uuids::Bool
    uses_base64::Bool
    datetime::Symbol
end

const JULIA_RESERVED_NAMES = Set([
    "baremodule",
    "begin",
    "break",
    "catch",
    "const",
    "continue",
    "do",
    "else",
    "elseif",
    "end",
    "export",
    "false",
    "finally",
    "for",
    "function",
    "global",
    "if",
    "import",
    "let",
    "local",
    "macro",
    "module",
    "quote",
    "return",
    "struct",
    "true",
    "try",
    "using",
    "while",
    "where",
    "mutable",
    "primitive",
    "abstract",
    "type",
    "Client",
    "ApiError",
    "Absent",
    "ABSENT",
])

const GENERATED_TYPE_NAMES = Set([
    "HTTP",
    "JSON",
    "OpenAPI",
    "SchemaEngine",
    "Base64",
    "Dates",
    "UUIDs",
    "Absent",
    "DecodeError",
    "ApiError",
    "ApiResponse",
    "UnexpectedBody",
    "UnsupportedMediaType",
    "UnexpectedContentType",
    "SchemaValidationError",
    "AbstractCredential",
    "ApiKeyCredential",
    "BasicCredential",
    "BearerCredential",
    "HttpCredential",
    "MutualTLSCredential",
    "Upload",
    "MultipartPartHeaders",
    "Client",
])

const GENERATED_PARAMETER_NAMES = Set([
    "body",
    "client",
    "content_type",
    "accept",
    "server",
    "with_http_info",
    "request_headers",
    "request_options",
    "multipart_headers",
    "stream_to",
])

function _words(value::AbstractString)
    normalized = replace(String(value), r"[^A-Za-z0-9]+" => " ")
    return [word for word in split(normalized) if !isempty(word)]
end

function _type_identifier(value::AbstractString)
    words = _words(value)
    output = isempty(words) ? "Model" : join(uppercasefirst(word) for word in words)
    isdigit(first(output)) && (output = "Model" * output)
    symbol = Symbol(output)
    if lowercase(output) in JULIA_RESERVED_NAMES ||
       output in GENERATED_TYPE_NAMES ||
       isdefined(Core, symbol) ||
       isdefined(Base, symbol)
        output *= "Model"
    end
    return output
end

function _field_identifier(value::AbstractString)
    words = _words(value)
    output = isempty(words) ? "value" : join(lowercase.(words), '_')
    isdigit(first(output)) && (output = "value_" * output)
    output in JULIA_RESERVED_NAMES && (output *= '_')
    Base.isidentifier(output) || (output = "value")
    return output
end

function _operation_identifier(value::AbstractString)
    output = _field_identifier(value)
    symbol = Symbol(output)
    (isdefined(Core, symbol) || isdefined(Base, symbol)) && (output *= '_')
    return output
end

function _allocate_name!(context::PlanningContext, suggested::AbstractString)
    base = _type_identifier(suggested)
    count = get(context.used_names, base, 0) + 1
    context.used_names[base] = count
    return count == 1 ? base : string(base, count)
end

function _canonical_node(view::SchemaView, node::Resources.NodeId)
    view.compiled === nothing && return node
    return Resources.canonical(view.compiled.registry, node)
end

function _child_view(view::SchemaView, tokens...)
    node = view.node
    value = view.value
    for token in tokens
        key = String(token)
        value = value isa AbstractDict ? value[key] : value[Base.parse(Int, key) + 1]
        node = _childnode(node, key)
        node = _canonical_node(view, node)
    end
    return SchemaView(value, node, view.version, view.compiled)
end

function _reference_target(view::SchemaView)
    view.value isa AbstractDict || return nothing
    raw = get(view.value, "\$ref", nothing)
    raw isa AbstractString || return nothing
    view.compiled === nothing && return nothing
    target = SchemaEngine.reference_target(view.compiled, view.node)
    target === nothing && return nothing
    resource = Resources.resource(view.compiled.registry, target.resource)
    value = Resources.resolve(resource.contents, target.pointer)
    return SchemaView(value, target, view.version, view.compiled)
end

const NON_APPLICATIVE_SCHEMA_SIBLINGS = Set([
    "\$comment",
    "title",
    "description",
    "default",
    "examples",
    "example",
    "deprecated",
    "readOnly",
    "writeOnly",
    "externalDocs",
    "xml",
])

function _resolved_view(view::SchemaView)
    target = _reference_target(view)
    target === nothing && return view
    view.version.minor == 0 && return target
    siblings = String[String(key) for key in keys(view.value) if key != "\$ref"]
    all(key -> key in NON_APPLICATIVE_SCHEMA_SIBLINGS, siblings) && return target
    return view
end

function _keyword_owner(
    view::SchemaView,
    keyword::AbstractString,
    seen = Set{Resources.NodeId}(),
)
    view.node in seen && return nothing
    push!(seen, view.node)
    try
        view.value isa AbstractDict || return nothing
        haskey(view.value, keyword) && return view
        target = _reference_target(view)
        if target !== nothing
            owner = _keyword_owner(target, keyword, seen)
            owner === nothing || return owner
        end
        allof = get(view.value, "allOf", nothing)
        if allof isa AbstractVector
            parent = _child_view(view, "allOf")
            for index in eachindex(allof)
                owner = _keyword_owner(
                    _child_view(parent, string(index - 1)),
                    keyword,
                    seen,
                )
                owner === nothing || return owner
            end
        end
        return nothing
    finally
        delete!(seen, view.node)
    end
end

const DIRECTIONAL_SINGLE_SCHEMA_KEYS = (
    "not",
    "if",
    "then",
    "else",
    "items",
    "contains",
    "additionalProperties",
    "unevaluatedProperties",
    "propertyNames",
    "contentSchema",
)
const DIRECTIONAL_ARRAY_SCHEMA_KEYS = ("allOf", "anyOf", "oneOf", "prefixItems")
const DIRECTIONAL_OBJECT_SCHEMA_KEYS = (
    "properties",
    "patternProperties",
    "dependentSchemas",
)

function _directional_view(view::SchemaView)
    target = _reference_target(view)
    return view.version.minor == 0 && target !== nothing ? target : view
end

function _directional_children(view::SchemaView)
    output = SchemaView[]
    value = view.value
    value isa AbstractDict || return output
    target = _reference_target(view)
    target === nothing || push!(output, target)
    for key in DIRECTIONAL_SINGLE_SCHEMA_KEYS
        raw = get(value, key, nothing)
        (raw isa AbstractDict || raw isa Bool) || continue
        push!(output, _child_view(view, key))
    end
    for key in DIRECTIONAL_ARRAY_SCHEMA_KEYS
        raw = get(value, key, nothing)
        raw isa AbstractVector || continue
        parent = _child_view(view, key)
        for index in eachindex(raw)
            push!(output, _child_view(parent, string(index - 1)))
        end
    end
    for key in DIRECTIONAL_OBJECT_SCHEMA_KEYS
        raw = get(value, key, nothing)
        raw isa AbstractDict || continue
        parent = _child_view(view, key)
        for name in keys(raw)
            push!(output, _child_view(parent, String(name)))
        end
    end
    return output
end

function _populate_directional_cache!(
    cache::Dict{Tuple{Resources.NodeId,String},Bool},
    root::SchemaView,
    keyword::String,
)
    views = Dict{Resources.NodeId,SchemaView}()
    reverse_edges = Dict{Resources.NodeId,Vector{Resources.NodeId}}()
    known = Dict{Resources.NodeId,Bool}()
    stack = SchemaView[root]
    while !isempty(stack)
        view = _directional_view(pop!(stack))
        node = view.node
        haskey(views, node) && continue
        views[node] = view
        key = (node, keyword)
        if haskey(cache, key)
            known[node] = cache[key]
            continue
        end
        for raw_child in _directional_children(view)
            child = _directional_view(raw_child)
            parents = get!(reverse_edges, child.node, Resources.NodeId[])
            node in parents || push!(parents, node)
            haskey(views, child.node) || push!(stack, child)
        end
    end

    reachable = Set{Resources.NodeId}()
    queue = Resources.NodeId[]
    for (node, view) in views
        value = view.value
        local_match = value isa AbstractDict && get(value, keyword, false) === true
        if local_match || get(known, node, false)
            push!(reachable, node)
            push!(queue, node)
        end
    end
    while !isempty(queue)
        node = pop!(queue)
        for parent in get(reverse_edges, node, Resources.NodeId[])
            parent in reachable && continue
            push!(reachable, parent)
            push!(queue, parent)
        end
    end
    for node in keys(views)
        cache[(node, keyword)] = node in reachable
    end
    return
end

function _has_directional_property(
    view::SchemaView,
    keyword::String,
    cache::Dict{Tuple{Resources.NodeId,String},Bool} =
        Dict{Tuple{Resources.NodeId,String},Bool}(),
)
    object = _directional_view(view)
    key = (object.node, keyword)
    haskey(cache, key) || _populate_directional_cache!(cache, object, keyword)
    return cache[key]
end

function _direction(context::PlanningContext, view::SchemaView, mode::Symbol)
    mode === :neutral && return :neutral
    mode === :input &&
        _has_directional_property(view, "readOnly", context.directional) &&
        return :input
    mode === :output &&
        _has_directional_property(view, "writeOnly", context.directional) &&
        return :output
    return :neutral
end

function _base_component_names(api::NormalizedAPI)
    output = Dict{Resources.NodeId,String}()
    for (name, handle) in api.schemas
        output[handle.node] = String(name)
        if handle.compiled !== nothing
            output[handle.compiled.root] = String(name)
            output[Resources.canonical(handle.compiled.registry, handle.node)] = String(name)
        end
    end
    return output
end

function PlanningContext(
    api::NormalizedAPI,
    bag::DiagnosticBag;
    datetime::Symbol = :utc,
)
    return PlanningContext(
        api,
        bag,
        Dict{Tuple{Resources.NodeId,Symbol},String}(),
        _base_component_names(api),
        Dict{String,Int}(),
        Set{Tuple{Resources.NodeId,Symbol}}(),
        Set{Tuple{Resources.NodeId,Symbol}}(),
        Dict{Tuple{Resources.NodeId,String},Bool}(),
        Dict{Resources.NodeId,Bool}(),
        ModelPlan[],
        false,
        false,
        false,
        datetime,
    )
end

function _validate_datetime_option(datetime::Symbol)
    datetime in (:utc, :zoned) || throw(
        ArgumentError(
            "datetime must be :utc (Dates.DateTime, offsets normalized to UTC) " *
            "or :zoned (TimeZones.ZonedDateTime, offsets preserved), got $(repr(datetime))",
        ),
    )
    return datetime
end

function _model_name!(context::PlanningContext, view::SchemaView, suggested, mode)
    direction = _direction(context, view, mode)
    resolved = _resolved_view(view)
    key = (resolved.node, direction)
    existing = get(context.names, key, nothing)
    existing === nothing || return existing, key, resolved
    base = get(context.base_names, resolved.node, String(suggested))
    suffix = direction === :input ? "Input" : direction === :output ? "Output" : ""
    name = _allocate_name!(context, base * suffix)
    context.names[key] = name
    return name, key, resolved
end

function _schema_types(value)
    value isa AbstractDict || return String[]
    raw = get(value, "type", nothing)
    raw isa AbstractString && return [String(raw)]
    raw isa AbstractVector && return String[String(item) for item in raw]
    return String[]
end

function _intersect_types(left::Vector{String}, right::Vector{String})
    isempty(left) && return copy(right)
    isempty(right) && return copy(left)
    return String[type for type in left if type in right]
end

function _effective_types(
    view::SchemaView,
    seen = Set{Resources.NodeId}(),
)
    view.node in seen && return String[]
    push!(seen, view.node)
    try
        value = view.value
        value isa AbstractDict || return String[]
        types = _schema_types(value)
        target = _reference_target(view)
        target === nothing ||
            (types = _intersect_types(types, _effective_types(target, seen)))
        allof = get(value, "allOf", nothing)
        if allof isa AbstractVector
            parent = _child_view(view, "allOf")
            for index in eachindex(allof)
                types = _intersect_types(
                    types,
                    _effective_types(
                        _child_view(parent, string(index - 1)),
                        seen,
                    ),
                )
            end
        end
        return unique(types)
    finally
        delete!(seen, view.node)
    end
end

function _structural_nullable(view::SchemaView, seen = Set{Resources.NodeId}())
    view.value === false && return false
    view.value === true && return true
    view.node in seen && return false
    push!(seen, view.node)
    value = view.value
    try
        view.version.minor == 0 && get(value, "nullable", false) === true && return true
        "null" in _effective_types(view) && return true
        for keyword in ("oneOf", "anyOf")
            owner = _keyword_owner(view, keyword)
            owner === nothing && continue
            alternatives = owner.value[keyword]
            alternatives isa AbstractVector || continue
            parent = _child_view(owner, keyword)
            any(eachindex(alternatives)) do index
                alternative = _child_view(parent, string(index - 1))
                return alternative.value isa AbstractDict &&
                       get(alternative.value, "type", nothing) == "null" ||
                       _structural_nullable(alternative, seen)
            end && return true
        end
        target = _reference_target(view)
        target === nothing || return _structural_nullable(target, seen)
        return false
    finally
        delete!(seen, view.node)
    end
end

function _nullable(context::PlanningContext, view::SchemaView)
    compiled = view.compiled
    if compiled !== nothing
        node = Resources.canonical(compiled.registry, view.node)
        return get!(context.nullable, node) do
            Base.isvalid(SchemaEngine.subschema(compiled, node), nothing)
        end
    end
    return _structural_nullable(view)
end

function _without_null_type(types::Vector{String})
    return [type for type in types if type != "null"]
end

function _primitive_type!(
    context::PlanningContext,
    type,
    format,
    mode::Symbol = :neutral,
)
    if type == "integer"
        return format == "int32" ? "Int32" : "Int64"
    elseif type == "number"
        return format == "float" ? "Float32" : "Float64"
    elseif type == "boolean"
        return "Bool"
    elseif type == "null"
        return "Nothing"
    elseif type == "string"
        if format == "date"
            context.uses_dates = true
            return "Dates.Date"
        elseif format == "date-time"
            context.uses_dates = true
            return context.datetime === :zoned ? "TimeZones.ZonedDateTime" :
                   "Dates.DateTime"
        elseif format == "time"
            context.uses_dates = true
            return "Dates.Time"
        elseif format == "uuid"
            context.uses_uuids = true
            return "UUIDs.UUID"
        elseif format in ("byte", "base64")
            context.uses_base64 = true
            return "Vector{UInt8}"
        elseif format == "binary"
            return mode === :input ? "Union{Vector{UInt8},Upload}" :
                   "Vector{UInt8}"
        end
        return "String"
    end
    return "Any"
end

function _union_string(types)
    unique_types = unique(String[type for type in types if type != "Union{}"])
    isempty(unique_types) && return "Any"
    "Any" in unique_types && return "Any"
    length(unique_types) == 1 && return only(unique_types)
    sort!(unique_types)
    return "Union{" * join(unique_types, ',') * "}"
end

function _field_type(base::String, required::Bool, nullable::Bool)
    variants = String[base]
    nullable && !occursin(r"\bNothing\b", base) && push!(variants, "Nothing")
    required || push!(variants, "Absent")
    return _union_string(variants)
end

function _is_object_schema(
    view::SchemaView,
    seen = Set{Resources.NodeId}(),
)
    view.node in seen && return false
    push!(seen, view.node)
    try
        value = view.value
        value isa AbstractDict || return false
        types = _schema_types(value)
        "object" in types && return true
        isempty(types) && any(
            haskey(value, key) for key in (
                "properties",
                "additionalProperties",
                "patternProperties",
                "unevaluatedProperties",
            )
        ) && return true
        target = _reference_target(view)
        target === nothing || _is_object_schema(target, seen) && return true
        allof = get(value, "allOf", nothing)
        allof isa AbstractVector || return false
        parent = _child_view(view, "allOf")
        return any(eachindex(allof)) do index
            _is_object_schema(_child_view(parent, string(index - 1)), seen)
        end
    finally
        delete!(seen, view.node)
    end
end

function _combine_additional(left, right)
    (left === false || right === false) && return false
    left === true && return right
    right === true && return left
    left_items = left isa AbstractVector ? copy(left) : SchemaView[left]
    right_items = right isa AbstractVector ? right : SchemaView[right]
    append!(left_items, right_items)
    unique!(item -> item.node, left_items)
    return left_items
end

function _local_additional(view::SchemaView)
    value = view.value
    value isa AbstractDict || return true
    patterns = SchemaView[]
    raw_patterns = get(value, "patternProperties", nothing)
    if raw_patterns isa AbstractDict
        parent = _child_view(view, "patternProperties")
        for name in keys(raw_patterns)
            push!(patterns, _child_view(parent, String(name)))
        end
    end
    keyword = haskey(value, "additionalProperties") ? "additionalProperties" :
              haskey(value, "unevaluatedProperties") ? "unevaluatedProperties" : nothing
    keyword === nothing && return true
    raw = value[keyword]
    raw === true && return true
    raw === false && return isempty(patterns) ? false : patterns
    push!(patterns, _child_view(view, keyword))
    return patterns
end

function _object_members(view::SchemaView, seen = Set{Resources.NodeId}())
    view.node in seen &&
        return Tuple{String,SchemaView,Bool,Bool,Bool}[], true
    push!(seen, view.node)
    members = Tuple{String,SchemaView,Bool,Bool,Bool}[]
    additional = true
    value = view.value
    try
        target = _reference_target(view)
        if target !== nothing
            target_members, target_additional = _object_members(target, seen)
            append!(members, target_members)
            additional = _combine_additional(additional, target_additional)
            view.version.minor == 0 && return target_members, target_additional
        end
        value isa AbstractDict || return members, additional
        required = Set(String.(get(value, "required", String[])))
        properties = get(value, "properties", nothing)
        if properties isa AbstractDict
            property_node = _child_view(view, "properties")
            for (name, raw) in properties
                child = _child_view(property_node, String(name))
                read_only = raw isa AbstractDict && get(raw, "readOnly", false) === true
                write_only = raw isa AbstractDict && get(raw, "writeOnly", false) === true
                push!(
                    members,
                    (String(name), child, String(name) in required, read_only, write_only),
                )
            end
        end
        additional = _combine_additional(additional, _local_additional(view))
        allof = get(value, "allOf", nothing)
        if allof isa AbstractVector
            parent = _child_view(view, "allOf")
            for index in eachindex(allof)
                child = _child_view(parent, string(index - 1))
                child_members, child_additional = _object_members(child, seen)
                append!(members, child_members)
                additional = _combine_additional(additional, child_additional)
            end
        end
    finally
        delete!(seen, view.node)
    end
    deduped = Tuple{String,SchemaView,Bool,Bool,Bool}[]
    positions = Dict{String,Int}()
    for member in members
        position = get(positions, member[1], 0)
        if position == 0
            push!(deduped, member)
            positions[member[1]] = length(deduped)
        else
            previous = deduped[position]
            deduped[position] = (
                member[1],
                member[2],
                previous[3] || member[3],
                previous[4] || member[4],
                previous[5] || member[5],
            )
        end
    end
    return deduped, additional
end

function _plan_enum!(context, view, suggested, mode, values)
    name, key, resolved = _model_name!(context, view, suggested, mode)
    key in context.planned && return name
    key in context.planning && return name
    push!(context.planning, key)
    value_types = unique(typeof(value) for value in values)
    alias = if all(value -> value isa AbstractString, values)
        "String"
    elseif all(value -> value isa Integer && !(value isa Bool), values)
        "Int64"
    elseif all(value -> value isa Real && !(value isa Bool), values)
        "Float64"
    elseif all(value -> value isa Bool, values)
        "Bool"
    else
        "Any"
    end
    push!(
        context.models,
        ModelPlan(
            name,
            :enum,
            (),
            Tuple(values),
            alias,
            nothing,
            nothing,
            (),
            nothing,
            (),
            key[2],
            Provenance(resolved.node),
        ),
    )
    delete!(context.planning, key)
    push!(context.planned, key)
    return name
end

function _plan_object!(context, view, suggested, mode)
    name, key, resolved = _model_name!(context, view, suggested, mode)
    key in context.planned && return name
    key in context.planning && return name
    push!(context.planning, key)
    members, additional = _object_members(resolved)
    fields = ModelFieldPlan[]
    used_fields = Dict("additional_properties" => 1)
    for (wire_name, child, required, read_only, write_only) in members
        mode === :input && read_only && continue
        mode === :output && write_only && continue
        field_name = _field_identifier(wire_name)
        count = get(used_fields, field_name, 0) + 1
        used_fields[field_name] = count
        count > 1 && (field_name = string(field_name, '_', count))
        base = _type_for!(context, child, name * _type_identifier(wire_name), mode)
        nullable = _nullable(context, child)
        # Response validation can be disabled to tolerate deployed APIs that
        # return explicit null for an optional, non-nullable property. Models
        # without readOnly/writeOnly properties are shared by input and output
        # planning, so every optional model field must be able to represent the
        # response value. Keep `Absent` for missing and `Nothing` for present
        # null; normal boundary validation still enforces the schema.
        decodable_null = nullable || !required
        default = required ? nothing : "ABSENT"
        push!(
            fields,
            ModelFieldPlan(
                field_name,
                wire_name,
                _field_type(base, required, decodable_null),
                required,
                nullable,
                default,
            ),
        )
    end
    additional_type = if additional === false
        nothing
    elseif additional isa AbstractVector
        _union_string(
            _type_for!(
                context,
                item,
                name * "AdditionalValue" * string(index),
                mode,
            ) for (index, item) in enumerate(additional)
        )
    elseif additional isa SchemaView
        _type_for!(context, additional, name * "AdditionalValue", mode)
    else
        "Any"
    end
    push!(
        context.models,
        ModelPlan(
            name,
            :object,
            Tuple(fields),
            (),
            nothing,
            additional_type,
            nothing,
            (),
            nothing,
            (),
            key[2],
            Provenance(resolved.node),
        ),
    )
    delete!(context.planning, key)
    push!(context.planned, key)
    return name
end

function _union_alternatives(view::SchemaView, keyword::String)
    raw = get(view.value, keyword, nothing)
    raw isa AbstractVector || return SchemaView[]
    parent = _child_view(view, keyword)
    return SchemaView[
        _child_view(parent, string(index - 1)) for index in eachindex(raw)
        if !(raw[index] isa AbstractDict && get(raw[index], "type", nothing) == "null")
    ]
end

function _reference_view(view::SchemaView, reference::AbstractString)
    view.compiled === nothing && return nothing
    resolved = Resources.resolve(
        view.compiled.registry,
        Resources.Reference(view.node.resource, reference),
    )
    (resolved.value isa AbstractDict || resolved.value isa Bool) || return nothing
    return SchemaView(
        resolved.value,
        Resources.canonical(view.compiled.registry, resolved.id),
        view.version,
        view.compiled,
    )
end

function _plan_union!(context, view, suggested, mode, keyword)
    resolved = _resolved_view(view)
    union_owner = something(_keyword_owner(resolved, keyword), resolved)
    alternatives = _union_alternatives(union_owner, keyword)
    discriminator_owner = _keyword_owner(resolved, "discriminator")
    discriminator = discriminator_owner === nothing ? nothing :
                    discriminator_owner.value["discriminator"]
    if !haskey(context.base_names, resolved.node) &&
       discriminator === nothing &&
       length(alternatives) == 1 &&
       _nullable(context, resolved)
        base = _type_for!(context, only(alternatives), suggested, mode)
        return _union_string((base, "Nothing"))
    end

    name, key, resolved = _model_name!(context, view, suggested, mode)
    key in context.planned && return name
    key in context.planning && return name
    push!(context.planning, key)

    alternative_types = String[
        _type_for!(context, alternative, suggested * string(index), mode) for
        (index, alternative) in enumerate(alternatives)
    ]
    types = copy(alternative_types)
    _nullable(context, resolved) && push!(types, "Nothing")
    property_name = discriminator isa AbstractDict &&
                    get(discriminator, "propertyName", nothing) isa AbstractString ?
                    String(discriminator["propertyName"]) : nothing
    mapping_by_tag = Dict{String,Pair{Resources.NodeId,String}}()
    variants = Pair{Resources.NodeId,String}[
        _resolved_view(alternative).node => alternative_types[index] for
        (index, alternative) in enumerate(alternatives)
    ]
    if property_name !== nothing
        for (index, alternative) in enumerate(alternatives)
            target = _resolved_view(alternative).node
            tag = get(context.base_names, target, nothing)
            tag === nothing ||
                (mapping_by_tag[tag] = target => alternative_types[index])
        end
    end
    if discriminator isa AbstractDict &&
       get(discriminator, "mapping", nothing) isa AbstractDict
        for (tag, reference) in discriminator["mapping"]
            reference isa AbstractString || continue
            target = try
                _reference_view(resolved, reference)
            catch error
                _error!(
                    context.bag,
                    :invalid_discriminator_mapping,
                    "cannot resolve discriminator mapping $(repr(tag)): $(sprint(showerror, error))",
                    SourceLocation(resolved.node.resource, resolved.node.pointer),
                )
                missing
            end
            target === missing && continue
            if target === nothing
                _error!(
                    context.bag,
                    :invalid_discriminator_mapping,
                    "discriminator mapping $(repr(tag)) does not resolve to a schema",
                    SourceLocation(resolved.node.resource, resolved.node.pointer),
                )
                continue
            end
            target_type = _type_for!(
                context,
                target,
                suggested * _type_identifier(String(tag)),
                mode,
            )
            push!(types, target_type)
            mapping_by_tag[String(tag)] = target.node => target_type
        end
    end
    mapping = sort!(collect(mapping_by_tag); by = first)

    default_mapping = nothing
    if discriminator isa AbstractDict &&
       get(discriminator, "defaultMapping", nothing) isa AbstractString
        target = try
            _reference_view(resolved, discriminator["defaultMapping"])
        catch error
            _error!(
                context.bag,
                :invalid_discriminator_default,
                "cannot resolve discriminator defaultMapping: $(sprint(showerror, error))",
                SourceLocation(resolved.node.resource, resolved.node.pointer),
            )
            missing
        end
        if target === missing
            nothing
        elseif target === nothing
            _error!(
                context.bag,
                :invalid_discriminator_default,
                "discriminator defaultMapping does not resolve to a schema",
                SourceLocation(resolved.node.resource, resolved.node.pointer),
            )
        else
            target_type = _type_for!(context, target, suggested * "Default", mode)
            push!(types, target_type)
            default_mapping = target.node => target_type
        end
    end
    union_type = _union_string(types)
    push!(
        context.models,
        ModelPlan(
            name,
            keyword == "oneOf" ? :oneof : :anyof,
            (),
            Tuple(types),
            union_type,
            nothing,
            property_name,
            Tuple(mapping),
            default_mapping,
            Tuple(variants),
            key[2],
            Provenance(resolved.node),
        ),
    )
    delete!(context.planning, key)
    push!(context.planned, key)
    return name
end

function _schema_keyword(view::SchemaView, keyword::AbstractString, default = nothing)
    owner = _keyword_owner(view, keyword)
    return owner === nothing ? default : owner.value[keyword]
end

function _array_type!(context, view::SchemaView, suggested, mode)
    prefix_owner = _keyword_owner(view, "prefixItems")
    items_owner = _keyword_owner(view, "items")
    if prefix_owner !== nothing &&
       prefix_owner.value["prefixItems"] isa AbstractVector
        raw_prefix = prefix_owner.value["prefixItems"]
        parent = _child_view(prefix_owner, "prefixItems")
        prefix_types = String[
            _type_for!(
                context,
                _child_view(parent, string(index - 1)),
                suggested * string(index),
                mode,
            ) for index in eachindex(raw_prefix)
        ]
        raw_items = items_owner === nothing ? true : items_owner.value["items"]
        minimum = _schema_keyword(view, "minItems", 0)
        maximum = _schema_keyword(view, "maxItems", nothing)
        exact = raw_items === false &&
                minimum isa Integer && minimum == length(prefix_types) &&
                (maximum === nothing || maximum == length(prefix_types))
        exact && return "Tuple{" * join(prefix_types, ',') * "}"
        element_types = copy(prefix_types)
        if raw_items === true
            push!(element_types, "Any")
        elseif raw_items isa AbstractDict || raw_items isa Bool
            raw_items === false || push!(
                element_types,
                _type_for!(
                    context,
                    _child_view(items_owner, "items"),
                    suggested * "Rest",
                    mode,
                ),
            )
        end
        return "Vector{" * _union_string(element_types) * "}"
    end
    if items_owner !== nothing
        raw_items = items_owner.value["items"]
        if raw_items isa AbstractDict || raw_items isa Bool
            raw_items === false && return "Vector{Union{}}"
            raw_items === true && return "Vector{Any}"
            item = _child_view(items_owner, "items")
            return "Vector{" *
                   _type_for!(context, item, suggested * "Item", mode) * "}"
        end
    end
    return "Vector{Any}"
end

function _primitive_format(view::SchemaView)
    format = _schema_keyword(view, "format", nothing)
    encoding = _schema_keyword(view, "contentEncoding", nothing)
    encoding == "base64" && return "base64"
    return format
end

function _type_for!(
    context::PlanningContext,
    original::SchemaView,
    suggested::AbstractString,
    mode::Symbol,
)
    view = _resolved_view(original)
    value = view.value
    value === true && return "Any"
    value === false && return "Union{}"
    enum = _schema_keyword(view, "enum", nothing)
    enum isa AbstractVector && !isempty(enum) &&
        return _plan_enum!(context, view, suggested, mode, enum)
    const_owner = _keyword_owner(view, "const")
    if const_owner !== nothing
        constant = const_owner.value["const"]
        return _primitive_type!(
            context,
            constant isa Bool ? "boolean" : constant isa Integer ? "integer" :
            constant isa Real ? "number" : constant isa AbstractString ? "string" :
            constant === nothing ? "null" : "",
            nothing,
            mode,
        )
    end
    for keyword in ("oneOf", "anyOf")
        _keyword_owner(view, keyword) === nothing ||
            return _plan_union!(context, view, suggested, mode, keyword)
    end
    types = _without_null_type(_effective_types(view))
    object_schema = _is_object_schema(view)
    if isempty(types)
        if object_schema
            return _plan_object!(context, view, suggested, mode)
        elseif _keyword_owner(view, "items") !== nothing ||
               _keyword_owner(view, "prefixItems") !== nothing
            types = ["array"]
        else
            return "Any"
        end
    end
    if types == ["object"]
        return _plan_object!(context, view, suggested, mode)
    end
    alias_state = nothing
    component_name = get(context.base_names, view.node, nothing)
    if component_name !== nothing && !("object" in types)
        name, key, resolved = _model_name!(context, view, suggested, mode)
        key in context.planned && return name
        key in context.planning && return name
        push!(context.planning, key)
        alias_state = (name, key, resolved)
    end
    output = String[]
    for type in types
        if type == "object"
            push!(output, _plan_object!(context, view, suggested, mode))
        elseif type == "array"
            push!(output, _array_type!(context, view, suggested, mode))
        else
            push!(
                output,
                _primitive_type!(
                    context,
                    type,
                    _primitive_format(view),
                    mode,
                ),
            )
        end
    end
    base = _union_string(output)
    if _nullable(context, view) && base != "Nothing"
        base = _union_string((base, "Nothing"))
    end
    if alias_state !== nothing
        name, key, resolved = alias_state
        push!(
            context.models,
            ModelPlan(
                name,
                :alias,
                (),
                (),
                base,
                nothing,
                nothing,
                (),
                nothing,
                (),
                key[2],
                Provenance(resolved.node),
            ),
        )
        delete!(context.planning, key)
        push!(context.planned, key)
        return name
    end
    return base
end

function _schema_type!(context, schema, suggested, mode)
    schema === nothing && return "Any"
    return _type_for!(context, SchemaView(schema), suggested, mode)
end

function _media_type!(
    context,
    media::NormalizedMediaType,
    suggested,
    mode;
    parameter::Bool = false,
)
    media.schema === nothing ||
        return _schema_type!(context, media.schema, suggested, mode)
    base = lowercase(strip(first(split(media.content_type, ';'; limit = 2))))
    (base == "application/json" || endswith(base, "+json")) && return "Any"
    startswith(base, "text/") && return "String"
    parameter && return "String"
    return mode === :input ? "Union{String,Vector{UInt8},Upload}" :
           "Vector{UInt8}"
end

function _parameter_schema(parameter::NormalizedParameter)
    parameter.schema !== nothing && return parameter.schema
    isempty(parameter.content) && return nothing
    return first(parameter.content).schema
end

function _plan_parameters!(context, operation, function_name)
    output = ParameterPlan[]
    used = Dict(name => 1 for name in GENERATED_PARAMETER_NAMES)
    for parameter in operation.parameters
        name = _field_identifier(parameter.name)
        count = get(used, name, 0) + 1
        used[name] = count
        count > 1 && (name = string(name, '_', count))
        parameter_schema = _parameter_schema(parameter)
        base = if parameter.schema === nothing && !isempty(parameter.content)
            _media_type!(
                context,
                first(parameter.content),
                _type_identifier(function_name) * _type_identifier(parameter.name),
                :input;
                parameter = true,
            )
        else
            _schema_type!(
                context,
                parameter_schema,
                _type_identifier(function_name) * _type_identifier(parameter.name),
                :input,
            )
        end
        type = _field_type(
            base,
            parameter.required,
            parameter_schema === nothing ? false :
            _nullable(context, SchemaView(parameter_schema)),
        )
        push!(
            output,
            ParameterPlan(
                name,
                parameter.name,
                parameter.location,
                type,
                parameter.required,
                parameter.style,
                parameter.explode,
                parameter.allow_reserved,
                parameter,
            ),
        )
    end
    return output
end

function _plan_request_body!(context, operation, function_name)
    body = operation.request_body
    body === nothing && return nothing
    media_types = Pair{String,String}[]
    for media in body.content
        type = _media_type!(
            context,
            media,
            _type_identifier(function_name) * "Request",
            :input,
        )
        push!(media_types, media.content_type => type)
    end
    base = isempty(media_types) ? "Any" : _union_string(last.(media_types))
    type = _field_type(base, body.required, false)
    return RequestBodyPlan("body", type, body.required, Tuple(media_types), body)
end

function _plan_responses!(context, operation, function_name)
    output = ResponsePlan[]
    success_types = String[]
    for response in operation.responses
        media_types = Pair{String,String}[]
        for media in response.content
            type = _media_type!(
                context,
                media,
                _type_identifier(function_name) * "Response" *
                replace(response.selector, r"[^A-Za-z0-9]" => ""),
                :output,
            )
            push!(media_types, media.content_type => type)
        end
        header_types = Pair{String,String}[]
        for header in response.headers
            schema = header.schema !== nothing ? header.schema :
                     isempty(header.content) ? nothing : first(header.content).schema
            type = _schema_type!(
                context,
                schema,
                _type_identifier(function_name) *
                _type_identifier(response.selector) *
                _type_identifier(header.name) * "Header",
                :output,
            )
            push!(header_types, header.name => type)
        end
        push!(
            output,
            ResponsePlan(
                response.selector,
                Tuple(media_types),
                Tuple(header_types),
                response,
            ),
        )
        selector = uppercase(response.selector)
        if startswith(selector, "2") || selector == "DEFAULT"
            if isempty(media_types)
                push!(success_types, "Nothing")
            else
                append!(success_types, last.(media_types))
            end
        end
    end
    if isempty(success_types)
        if isempty(operation.responses)
            append!(success_types, ("Nothing", "Vector{UInt8}"))
        else
            push!(success_types, "Nothing")
        end
    end
    return output, _union_string(success_types)
end

function _plan_operation!(context, operation, used_functions)
    base = _operation_identifier(operation.id)
    count = get(used_functions, base, 0) + 1
    used_functions[base] = count
    name = count == 1 ? base : string(base, '_', count)
    parameters = _plan_parameters!(context, operation, name)
    request = _plan_request_body!(context, operation, name)
    responses, return_type = _plan_responses!(context, operation, name)
    return OperationPlan(
        name,
        operation,
        Tuple(parameters),
        request,
        Tuple(responses),
        return_type,
    )
end

function _has_positional_encoding(encoding::NormalizedEncoding)
    return haskey(encoding.raw, "itemEncoding") ||
           haskey(encoding.raw, "prefixEncoding") ||
           any(_has_positional_encoding, encoding.encoding)
end

function _encoding_value_schema(view::SchemaView)
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

function _planning_content_base(content_type)
    content_type === nothing && return ""
    selected = strip(first(split(String(content_type), ','; limit = 2)))
    return lowercase(strip(first(split(selected, ';'; limit = 2))))
end

function _check_named_encodings!(
    context::PlanningContext,
    encodings,
    schema::Union{Nothing,SchemaView},
)
    members = schema === nothing ? Tuple{String,SchemaView,Bool,Bool,Bool}[] :
              first(_object_members(schema))
    known = Dict(member[1] => member[2] for member in members)
    for encoding in encodings
        property = get(known, encoding.name, nothing)
        if property === nothing
            _warning!(
                context.bag,
                :ignored_encoding_property,
                "encoding key $(repr(encoding.name)) has no corresponding schema property and is ignored",
                SourceLocation(
                    encoding.provenance.node.resource,
                    encoding.provenance.node.pointer,
                ),
            )
            continue
        end
        isempty(encoding.encoding) && continue
        base = _planning_content_base(encoding.content_type)
        if !(base == "application/x-www-form-urlencoded" ||
             startswith(base, "multipart/"))
            _error!(
                context.bag,
                :invalid_nested_encoding_media_type,
                "nested named encodings require an explicit multipart or application/x-www-form-urlencoded contentType",
                SourceLocation(
                    encoding.provenance.node.resource,
                    encoding.provenance.node.pointer,
                ),
            )
            continue
        end
        _check_named_encodings!(
            context,
            encoding.encoding,
            _encoding_value_schema(property),
        )
    end
    return
end

function _check_generation_support!(context::PlanningContext, strict::Bool)
    for operation in context.api.operations
        operation.direction === :request || continue
        for parameter in operation.parameters
            parameter.location === :querystring || continue
            _error!(
                context.bag,
                :unsupported_querystring_generation,
                "OAS 3.2 querystring parameter generation is not implemented",
                SourceLocation(
                    parameter.provenance.node.resource,
                    parameter.provenance.node.pointer,
                ),
            )
        end
        for parameter in operation.parameters
            parameter.schema === nothing && continue
            view = SchemaView(parameter.schema)
            types = _without_null_type(_effective_types(view))
            array_schema = "array" in types ||
                           _keyword_owner(view, "items") !== nothing ||
                           _keyword_owner(view, "prefixItems") !== nothing
            if parameter.style === :deepObject && !_is_object_schema(view)
                emit = strict ? _error! : _warning!
                emit(
                    context.bag,
                    :invalid_deep_object_schema,
                    strict ?
                    "deepObject serialization requires an object schema" :
                    "non-object deepObject schema uses non-standard bracket compatibility serialization",
                    SourceLocation(
                        parameter.provenance.node.resource,
                        parameter.provenance.node.pointer,
                    ),
                )
            elseif parameter.style in (:spaceDelimited, :pipeDelimited) &&
                   !array_schema
                _error!(
                    context.bag,
                    :invalid_delimited_schema,
                    "$(parameter.style) serialization requires an array schema",
                    SourceLocation(
                        parameter.provenance.node.resource,
                        parameter.provenance.node.pointer,
                    ),
                )
            end
        end
        media_types = NormalizedMediaType[]
        operation.request_body === nothing ||
            append!(media_types, operation.request_body.content)
        for response in operation.responses
            append!(media_types, response.content)
        end
        for media in media_types
            streaming = media.item_schema !== nothing ||
                        haskey(media.raw, "itemEncoding") ||
                        haskey(media.raw, "prefixEncoding") ||
                        any(
                _has_positional_encoding,
                media.encoding,
            )
            streaming || continue
            _error!(
                context.bag,
                :unsupported_streaming_generation,
                "streaming itemSchema and positional encoding generation is not implemented",
                SourceLocation(
                    media.provenance.node.resource,
                    media.provenance.node.pointer,
                ),
            )
        end
        if operation.request_body !== nothing
            for media in operation.request_body.content
                isempty(media.encoding) && continue
                _check_named_encodings!(
                    context,
                    media.encoding,
                    media.schema === nothing ? nothing : SchemaView(media.schema),
                )
            end
        end
    end
    return
end

function _plan_components!(context::PlanningContext)
    api = context.api
    # Reserve stable component names before recursive planning starts.
    for (component_name, handle) in sort(collect(api.schemas); by = first)
        view = SchemaView(handle)
        resolved = _resolved_view(view)
        key = (resolved.node, :neutral)
        haskey(context.names, key) ||
            (context.names[key] = _allocate_name!(context, component_name))
    end
    for (component_name, handle) in sort(collect(api.schemas); by = first)
        _type_for!(context, SchemaView(handle), component_name, :neutral)
    end
    operations = OperationPlan[]
    used_functions = Dict{String,Int}()
    ordered = sort(
        [operation for operation in api.operations if operation.direction === :request];
        by = operation -> (operation.path, String(operation.method), operation.id),
    )
    for operation in ordered
        push!(operations, _plan_operation!(context, operation, used_functions))
    end
    return operations
end

function _finish_diagnostics(context::PlanningContext, summary::AbstractString)
    diagnostics = Diagnostic[context.api.diagnostics...]
    append!(diagnostics, context.bag.diagnostics)
    _throw_on_errors(summary, diagnostics)
    return Tuple(diagnostics)
end

"""Build the deterministic Julia model and operation plan used by code generation."""
function plan(
    source;
    name::AbstractString = "ApiClient",
    strict::Bool = true,
    max_diagnostics::Integer = 1_000,
    datetime::Symbol = :utc,
    kwargs...,
)
    _validate_datetime_option(datetime)
    api = source isa NormalizedAPI ? source :
          normalize(source; strict, max_diagnostics, kwargs...)
    bag = DiagnosticBag(max_diagnostics)
    context = PlanningContext(api, bag; datetime)
    _check_generation_support!(context, strict)
    operations = _plan_components!(context)
    diagnostics = _finish_diagnostics(context, "Cannot plan Julia client")
    # Recursive planning emits dependencies before parents. Sort only aliases and
    # enums that do not depend on declaration order; object order stays topological.
    return ClientPlan(
        api,
        _type_identifier(name),
        Tuple(context.models),
        Tuple(operations),
        diagnostics,
        context.uses_dates,
        context.uses_uuids,
        context.uses_base64,
        context.datetime,
    )
end

function _check_server_generation_support!(context::PlanningContext, strict::Bool)
    for operation in context.api.operations
        operation.direction === :request || continue
        # A form-style exploded object query or cookie parameter consumes
        # arbitrary wire names. One such parameter per location decodes from the
        # pairs no other declared parameter claimed; two or more are ambiguous.
        for location in (:query, :cookie)
            exploded = NormalizedParameter[
                parameter for parameter in operation.parameters
                if parameter.location === location &&
                   parameter.style === :form &&
                   parameter.explode === true &&
                   _schema_shape(_parameter_schema(parameter)) === :object
            ]
            length(exploded) > 1 && _error!(
                context.bag,
                :ambiguous_exploded_object_parameters,
                "multiple form-style exploded object $location parameters cannot be decoded unambiguously",
                SourceLocation(
                    exploded[2].provenance.node.resource,
                    exploded[2].provenance.node.pointer,
                ),
            )
        end
        operation.request_body === nothing && continue
        for media in operation.request_body.content
            base = _planning_content_base(media.content_type)
            if startswith(base, "multipart/") && base != "multipart/form-data"
                _error!(
                    context.bag,
                    :unsupported_multipart_server_generation,
                    "server generation only decodes multipart/form-data request bodies",
                    SourceLocation(
                        media.provenance.node.resource,
                        media.provenance.node.pointer,
                    ),
                )
            end
            for encoding in media.encoding
                if !isempty(encoding.encoding)
                    _error!(
                        context.bag,
                        :unsupported_nested_server_encoding,
                        "server generation cannot decode nested request-body Encoding Objects",
                        SourceLocation(
                            encoding.provenance.node.resource,
                            encoding.provenance.node.pointer,
                        ),
                    )
                end
                if startswith(base, "multipart/") && !isempty(encoding.headers)
                    _error!(
                        context.bag,
                        :unsupported_multipart_server_headers,
                        "server generation cannot recover custom multipart part headers",
                        SourceLocation(
                            encoding.provenance.node.resource,
                            encoding.provenance.node.pointer,
                        ),
                    )
                end
                if base in ("application/x-www-form-urlencoded", "multipart/form-data") &&
                   (
                    encoding.style !== nothing ||
                    encoding.explode !== nothing ||
                    haskey(encoding.raw, "allowReserved")
                )
                    _error!(
                        context.bag,
                        :unsupported_server_encoding_style,
                        "server generation cannot invert explicit request-body encoding style, explode, or allowReserved fields",
                        SourceLocation(
                            encoding.provenance.node.resource,
                            encoding.provenance.node.pointer,
                        ),
                    )
                end
            end
        end
    end
    return
end

"""
    OpenAPI.serverplan(source; name="ApiServer", strict=true, options...) -> ServerPlan

Build the deterministic Julia model and operation plan used by server stub
generation. Accepts the same sources and options as [`OpenAPI.plan`](@ref) and
additionally rejects documents whose requests cannot be decoded faithfully on
the server side.
"""
function serverplan(
    source;
    name::AbstractString = "ApiServer",
    strict::Bool = true,
    max_diagnostics::Integer = 1_000,
    datetime::Symbol = :utc,
    kwargs...,
)
    _validate_datetime_option(datetime)
    api = source isa NormalizedAPI ? source :
          normalize(source; strict, max_diagnostics, kwargs...)
    bag = DiagnosticBag(max_diagnostics)
    context = PlanningContext(api, bag; datetime)
    _check_generation_support!(context, strict)
    _check_server_generation_support!(context, strict)
    operations = _plan_components!(context)
    diagnostics = _finish_diagnostics(context, "Cannot plan Julia server")
    return ServerPlan(
        api,
        _type_identifier(name),
        Tuple(context.models),
        Tuple(operations),
        diagnostics,
        context.uses_dates,
        context.uses_uuids,
        context.uses_base64,
        context.datetime,
    )
end
