# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

mutable struct EvaluationResult
    valid::Bool
    issues::Union{Nothing,Vector{SingleIssue}}
    properties::Union{Nothing,Set{String}}
    items::Union{Nothing,BitSet}
end

function EvaluationResult()
    return EvaluationResult(true, nothing, nothing, nothing)
end

mutable struct EvaluationPath
    parent::Union{Nothing,EvaluationPath}
    token::String
    depth::Int
end

EvaluationPath() = EvaluationPath(nothing, "", 0)
function EvaluationPath(parent::EvaluationPath, token::AbstractString)
    return EvaluationPath(parent, String(token), parent.depth + 1)
end

function _path_string(path::EvaluationPath)
    path.depth == 0 && return ""
    tokens = Vector{String}(undef, path.depth)
    current = path
    for index in path.depth:-1:1
        tokens[index] = current.token
        current = current.parent::EvaluationPath
    end
    return string(Resources.JSONPointer(Tuple(tokens)))
end

mutable struct EvaluationContext
    schema::CompiledSchema
    active::Set{Tuple{Int,EvaluationPath,Tuple{Vararg{Resources.ResourceId}}}}
    regexes::Dict{String,Regex}
    evaluations::Int
    depth::Int
    max_evaluations::Int
    max_issues::Int
    max_depth::Int
    collect_all::Bool
    annotations::Bool
    tracks_cycles::Bool
end

function EvaluationContext(
    schema::CompiledSchema,
    max_evaluations::Integer,
    max_issues::Integer,
    max_depth::Integer,
    collect_all::Bool,
)
    max_evaluations > 0 ||
        throw(ArgumentError("max_evaluations must be positive"))
    max_issues > 0 || throw(ArgumentError("max_issues must be positive"))
    max_depth > 0 || throw(ArgumentError("max_depth must be positive"))
    return EvaluationContext(
        schema,
        Set{Tuple{Int,EvaluationPath,Tuple{Vararg{Resources.ResourceId}}}}(),
        copy(getfield(schema, :regexes)),
        0,
        0,
        Int(max_evaluations),
        Int(max_issues),
        Int(max_depth),
        collect_all,
        getfield(schema, :uses_annotations),
        !isempty(getfield(schema, :references)),
    )
end

struct EvaluationError <: Exception
    schema::Resources.NodeId
    instance::String
    reason::String
end

function Base.showerror(io::IO, err::EvaluationError)
    pointer = string(err.schema.pointer)
    location =
        string(err.schema.resource) * (isempty(pointer) ? "" : "#" * pointer)
    instance =
        isempty(err.instance) ? "the instance root" :
        "instance " * repr(err.instance)
    return print(
        io,
        "cannot evaluate JSON Schema at ",
        repr(location),
        " for ",
        instance,
        ": ",
        err.reason,
    )
end

function _regex(context::EvaluationContext, pattern::AbstractString)
    normalized = String(pattern)
    return get!(context.regexes, normalized) do
        return _ecma_regex(normalized)
    end
end

function _invalidate!(
    result::EvaluationResult,
    context::EvaluationContext,
    issue::SingleIssue,
)
    !context.collect_all && !result.valid && return result
    if context.collect_all
        issue_count = result.issues === nothing ? 0 : length(result.issues)
        issue_count < context.max_issues || throw(
            EvaluationError(
                context.schema.root,
                issue.path,
                "the issue limit was reached",
            ),
        )
    end
    result.valid = false
    result.issues === nothing && (result.issues = SingleIssue[])
    push!(result.issues::Vector{SingleIssue}, issue)
    return result
end

function _merge_annotations!(result::EvaluationResult, child::EvaluationResult)
    if child.properties !== nothing
        if result.properties === nothing
            result.properties = copy(child.properties)
        else
            union!(result.properties::Set{String}, child.properties)
        end
    end
    if child.items !== nothing
        if result.items === nothing
            result.items = copy(child.items)
        else
            union!(result.items::BitSet, child.items)
        end
    end
    return result
end

function _mark_property!(result::EvaluationResult, name::String)
    result.properties === nothing && (result.properties = Set{String}())
    push!(result.properties::Set{String}, name)
    return result
end

function _mark_item!(result::EvaluationResult, index::Int)
    result.items === nothing && (result.items = BitSet())
    push!(result.items::BitSet, index)
    return result
end

function _absorb!(
    result::EvaluationResult,
    context::EvaluationContext,
    child::EvaluationResult;
    annotations::Bool = true,
)
    if child.valid
        annotations && context.annotations && _merge_annotations!(result, child)
    else
        result.valid = false
        child_issues = something(child.issues, SingleIssue[])
        if context.collect_all
            issue_count = result.issues === nothing ? 0 : length(result.issues)
            issue_count + length(child_issues) <= context.max_issues || throw(
                EvaluationError(
                    context.schema.root,
                    isempty(child_issues) ? "" : first(child_issues).path,
                    "the issue limit was reached",
                ),
            )
            if !isempty(child_issues)
                result.issues === nothing && (result.issues = SingleIssue[])
                append!(result.issues::Vector{SingleIssue}, child_issues)
            end
        elseif result.issues === nothing && !isempty(child_issues)
            result.issues = SingleIssue[first(child_issues)]
        end
    end
    return result
end

function _stopped(context::EvaluationContext, result::EvaluationResult)
    return !context.collect_all && !result.valid
end

function _compiled_node(schema::CompiledSchema, raw::Resources.NodeId)
    nodes = getfield(schema, :evaluation_nodes)
    found = get(nodes, raw, nothing)
    found === nothing || return found
    canonical = Resources.canonical(schema.registry, raw)
    return get(
        () -> throw(
            EvaluationError(
                canonical,
                "",
                "the location was not compiled as a schema",
            ),
        ),
        nodes,
        canonical,
    )
end

function _canonical(schema::CompiledSchema, node::Resources.NodeId)
    return _compiled_node(schema, node).id
end

function _compiled_child(schema::CompiledSchema, node::Resources.NodeId, tokens)
    parent = _compiled_node(schema, node)
    key = (parent.index, tokens)
    return get(
        () -> throw(
            EvaluationError(
                parent.id,
                "",
                "the child location was not compiled as a schema",
            ),
        ),
        getfield(schema, :transitions),
        key,
    )
end

function _property_path(path::EvaluationPath, property)
    return EvaluationPath(path, string(property))
end

function _array_path(path::EvaluationPath, index::Integer)
    return EvaluationPath(path, string(index - 1))
end

function _issue(x, path::EvaluationPath, keyword::String, value)
    return SingleIssue(x, _path_string(path), keyword, value)
end

function _json_type(x, type::AbstractString)
    type == "null" && return x === nothing || x === missing
    type == "boolean" && return x isa Bool
    type == "object" && return x isa AbstractDict
    type == "array" && return x isa AbstractVector
    type == "string" && return x isa AbstractString
    if type == "integer"
        x isa Bool && return false
        return x isa Integer || (x isa Real && isinteger(x))
    end
    type == "number" && return x isa Real && !(x isa Bool)
    return false
end

function _type_valid(x, expected)
    expected isa AbstractString && return _json_type(x, expected)
    expected isa AbstractVector || return true
    return any(type -> type isa AbstractString && _json_type(x, type), expected)
end

function _multiple_of(x::Real, divisor::Real)
    divisor == 0 && return false
    ratio = x / divisor
    isfinite(ratio) || return false
    return isinteger(ratio) ||
           isapprox(ratio, round(ratio); rtol = 0, atol = eps(float(ratio)) * 4)
end

function _simple_assertions!(
    result::EvaluationResult,
    context::EvaluationContext,
    x,
    schema::AbstractDict,
    schema_dialect::Dialect,
    path::EvaluationPath,
)
    expected = get(schema, "type", nothing)
    if expected !== nothing && !_type_valid(x, expected)
        _invalidate!(result, context, _issue(x, path, "type", expected))
    end
    enum = get(schema, "enum", nothing)
    if enum isa AbstractVector && !any(value -> _isequal(x, value), enum)
        _invalidate!(result, context, _issue(x, path, "enum", enum))
    end
    if keyword_applies(schema_dialect, "const") &&
       haskey(schema, "const") &&
       !_isequal(x, schema["const"])
        _invalidate!(result, context, _issue(x, path, "const", schema["const"]))
    end
    if x isa Real && !(x isa Bool)
        multiple = get(schema, "multipleOf", nothing)
        if multiple isa Real && !_multiple_of(x, multiple)
            _invalidate!(
                result,
                context,
                _issue(x, path, "multipleOf", multiple),
            )
        end
        maximum = get(schema, "maximum", nothing)
        if maximum isa Real && x > maximum
            _invalidate!(result, context, _issue(x, path, "maximum", maximum))
        end
        minimum = get(schema, "minimum", nothing)
        if minimum isa Real && x < minimum
            _invalidate!(result, context, _issue(x, path, "minimum", minimum))
        end
        exclusive_maximum = get(schema, "exclusiveMaximum", nothing)
        if schema_dialect.name != :draft4 &&
           exclusive_maximum isa Real &&
           !(exclusive_maximum isa Bool) &&
           x >= exclusive_maximum
            _invalidate!(
                result,
                context,
                _issue(x, path, "exclusiveMaximum", exclusive_maximum),
            )
        elseif schema_dialect.name == :draft4 &&
               exclusive_maximum === true &&
               maximum isa Real &&
               x >= maximum
            _invalidate!(
                result,
                context,
                _issue(x, path, "exclusiveMaximum", exclusive_maximum),
            )
        end
        exclusive_minimum = get(schema, "exclusiveMinimum", nothing)
        if schema_dialect.name != :draft4 &&
           exclusive_minimum isa Real &&
           !(exclusive_minimum isa Bool) &&
           x <= exclusive_minimum
            _invalidate!(
                result,
                context,
                _issue(x, path, "exclusiveMinimum", exclusive_minimum),
            )
        elseif schema_dialect.name == :draft4 &&
               exclusive_minimum === true &&
               minimum isa Real &&
               x <= minimum
            _invalidate!(
                result,
                context,
                _issue(x, path, "exclusiveMinimum", exclusive_minimum),
            )
        end
    end
    if x isa AbstractString
        maximum = get(schema, "maxLength", nothing)
        maximum isa Real &&
            isinteger(maximum) &&
            length(x) > maximum &&
            _invalidate!(result, context, _issue(x, path, "maxLength", maximum))
        minimum = get(schema, "minLength", nothing)
        minimum isa Real &&
            isinteger(minimum) &&
            length(x) < minimum &&
            _invalidate!(result, context, _issue(x, path, "minLength", minimum))
        pattern = get(schema, "pattern", nothing)
        pattern isa AbstractString &&
            !occursin(_regex(context, pattern), x) &&
            _invalidate!(result, context, _issue(x, path, "pattern", pattern))
    elseif x isa AbstractVector
        maximum = get(schema, "maxItems", nothing)
        maximum isa Real &&
            isinteger(maximum) &&
            length(x) > maximum &&
            _invalidate!(result, context, _issue(x, path, "maxItems", maximum))
        minimum = get(schema, "minItems", nothing)
        minimum isa Real &&
            isinteger(minimum) &&
            length(x) < minimum &&
            _invalidate!(result, context, _issue(x, path, "minItems", minimum))
        if get(schema, "uniqueItems", false) === true
            for left in eachindex(x), right in firstindex(x):(left-1)
                if _isequal(x[left], x[right])
                    _invalidate!(
                        result,
                        context,
                        _issue(x, path, "uniqueItems", true),
                    )
                    break
                end
            end
        end
    elseif x isa AbstractDict
        maximum = get(schema, "maxProperties", nothing)
        maximum isa Real &&
            isinteger(maximum) &&
            length(x) > maximum &&
            _invalidate!(
                result,
                context,
                _issue(x, path, "maxProperties", maximum),
            )
        minimum = get(schema, "minProperties", nothing)
        minimum isa Real &&
            isinteger(minimum) &&
            length(x) < minimum &&
            _invalidate!(
                result,
                context,
                _issue(x, path, "minProperties", minimum),
            )
        required = get(schema, "required", nothing)
        if required isa AbstractVector
            all(name -> haskey(x, name), required) || _invalidate!(
                result,
                context,
                _issue(x, path, "required", required),
            )
        end
        dependent = get(schema, "dependentRequired", nothing)
        keyword_applies(schema_dialect, "dependentRequired") &&
            dependent isa AbstractDict &&
            _dependent_required!(
                result,
                context,
                x,
                dependent,
                path,
                "dependentRequired",
            )
        dependencies = get(schema, "dependencies", nothing)
        keyword_applies(schema_dialect, "dependencies") &&
            dependencies isa AbstractDict &&
            _dependent_required!(
                result,
                context,
                x,
                dependencies,
                path,
                "dependencies",
            )
    end
    return result
end

_simple_assertions!(result, context, x, ::Bool, schema_dialect, path) = result

function _dependent_required!(result, context, x, dependencies, path, keyword)
    for (property, required) in dependencies
        haskey(x, property) || continue
        required isa AbstractVector || continue
        all(name -> haskey(x, name), required) || _invalidate!(
            result,
            context,
            _issue(x, path, keyword, dependencies),
        )
    end
    return result
end

function _reference_target(
    context::EvaluationContext,
    node::Resources.NodeId,
    keyword::String,
    reference_text::AbstractString,
    dynamic_scope::Vector{Resources.ResourceId};
    dynamic::Bool = false,
    recursive::Bool = false,
)
    canonical_node = _canonical(context.schema, node)
    reference =
        dynamic ? Resources.Reference(canonical_node.resource, reference_text) :
        nothing
    target = get(
        getfield(context.schema, :references),
        (canonical_node, keyword),
        nothing,
    )
    if target === nothing
        target = try
            fallback = something(
                reference,
                Resources.Reference(canonical_node.resource, reference_text),
            )
            resolved = Resources.resolve(context.schema.registry, fallback)
            _canonical(context.schema, resolved.id)
        catch err
            throw(EvaluationError(canonical_node, "", sprint(showerror, err)))
        end
    end
    if dynamic && reference.fragment isa Resources.AnchorFragment
        name = reference.fragment.name
        if Resources.dynamic_anchor(
            context.schema.registry,
            target.resource,
            name,
        ) !== nothing
            for resource in dynamic_scope
                candidate = Resources.dynamic_anchor(
                    context.schema.registry,
                    resource,
                    name,
                )
                candidate === nothing ||
                    return _canonical(context.schema, candidate)
            end
        end
    elseif recursive &&
           target.resource in getfield(context.schema, :recursive_anchors)
        for resource in dynamic_scope
            resource in getfield(context.schema, :recursive_anchors) || continue
            return Resources.NodeId(resource, Resources.JSONPointer())
        end
    end
    return target
end

function _follow_reference(
    context::EvaluationContext,
    node::Resources.NodeId,
    keyword::String,
    reference_text::AbstractString,
    x,
    path::EvaluationPath,
    dynamic_scope::Vector{Resources.ResourceId};
    dynamic::Bool = false,
    recursive::Bool = false,
)
    target = _reference_target(
        context,
        node,
        keyword,
        reference_text,
        dynamic_scope;
        dynamic,
        recursive,
    )
    next_scope = dynamic_scope
    if isempty(dynamic_scope) || last(dynamic_scope) != target.resource
        next_scope = copy(dynamic_scope)
        push!(next_scope, target.resource)
    end
    return _evaluate_compiled_node(
        context,
        _compiled_node(context.schema, target),
        x,
        path,
        next_scope,
    )
end

function _references!(
    result::EvaluationResult,
    context::EvaluationContext,
    node::Resources.NodeId,
    x,
    schema::AbstractDict,
    schema_dialect::Dialect,
    path::EvaluationPath,
    dynamic_scope,
)
    reference = get(schema, "\$ref", nothing)
    if reference isa AbstractString
        child = _follow_reference(
            context,
            node,
            "\$ref",
            reference,
            x,
            path,
            dynamic_scope,
        )
        _absorb!(result, context, child)
        (_stopped(context, result) || !schema_dialect.ref_siblings) &&
            return false
    end
    if schema_dialect.dynamic_refs
        reference = get(schema, "\$dynamicRef", nothing)
        if reference isa AbstractString
            child = _follow_reference(
                context,
                node,
                "\$dynamicRef",
                reference,
                x,
                path,
                dynamic_scope;
                dynamic = true,
            )
            _absorb!(result, context, child)
            _stopped(context, result) && return false
        end
    elseif schema_dialect.recursive_refs
        reference = get(schema, "\$recursiveRef", nothing)
        if reference isa AbstractString
            child = _follow_reference(
                context,
                node,
                "\$recursiveRef",
                reference,
                x,
                path,
                dynamic_scope;
                recursive = true,
            )
            _absorb!(result, context, child)
            _stopped(context, result) && return false
        end
    end
    return true
end

function _child_result(context, node, tokens, x, path, dynamic_scope)
    child = _compiled_child(context.schema, node, tokens)
    return _evaluate_compiled_node(context, child, x, path, dynamic_scope)
end

function _combinators!(
    result,
    context,
    node,
    x,
    schema::AbstractDict,
    schema_dialect::Dialect,
    path,
    dynamic_scope,
)
    for keyword in ("allOf",)
        schemas = get(schema, keyword, nothing)
        schemas isa AbstractVector || continue
        for index in eachindex(schemas)
            child = _child_result(
                context,
                node,
                (keyword, string(index - 1)),
                x,
                path,
                dynamic_scope,
            )
            _absorb!(result, context, child)
            _stopped(context, result) && return result
        end
    end
    for keyword in ("anyOf", "oneOf")
        schemas = get(schema, keyword, nothing)
        schemas isa AbstractVector || continue
        valid = EvaluationResult[]
        for index in eachindex(schemas)
            child = _child_result(
                context,
                node,
                (keyword, string(index - 1)),
                x,
                path,
                dynamic_scope,
            )
            child.valid && push!(valid, child)
        end
        expected = keyword == "anyOf" ? !isempty(valid) : length(valid) == 1
        if expected
            for child in valid
                _absorb!(result, context, child)
            end
        else
            _invalidate!(result, context, _issue(x, path, keyword, schemas))
            _stopped(context, result) && return result
        end
    end
    negated = get(schema, "not", nothing)
    if negated isa AbstractDict || negated isa Bool
        child = _child_result(context, node, ("not",), x, path, dynamic_scope)
        if child.valid
            _invalidate!(result, context, _issue(x, path, "not", negated))
            _stopped(context, result) && return result
        end
    end
    condition = get(schema, "if", nothing)
    if keyword_applies(schema_dialect, "if") &&
       (condition isa AbstractDict || condition isa Bool)
        child = _child_result(context, node, ("if",), x, path, dynamic_scope)
        child.valid && _absorb!(result, context, child)
        branch = child.valid ? "then" : "else"
        selected = get(schema, branch, nothing)
        if selected isa AbstractDict || selected isa Bool
            branch_result =
                _child_result(context, node, (branch,), x, path, dynamic_scope)
            _absorb!(result, context, branch_result)
            _stopped(context, result) && return result
        end
    end
    return result
end

function _object_applicators!(
    result,
    context,
    node,
    x::AbstractDict,
    schema::AbstractDict,
    schema_dialect::Dialect,
    path,
    dynamic_scope,
)
    additional = get(schema, "additionalProperties", nothing)
    tracks_coverage = additional isa AbstractDict || additional isa Bool
    covered = tracks_coverage ? Set{String}() : nothing
    properties = get(schema, "properties", nothing)
    if properties isa AbstractDict
        for (name, subschema) in properties
            haskey(x, name) || continue
            (subschema isa AbstractDict || subschema isa Bool) || continue
            child = _child_result(
                context,
                node,
                ("properties", String(name)),
                x[name],
                _property_path(path, name),
                dynamic_scope,
            )
            _absorb!(result, context, child; annotations = false)
            _stopped(context, result) && return result
            tracks_coverage && push!(covered::Set{String}, String(name))
            context.annotations && _mark_property!(result, String(name))
        end
    end
    patterns = get(schema, "patternProperties", nothing)
    if patterns isa AbstractDict
        for (pattern, subschema) in patterns
            (subschema isa AbstractDict || subschema isa Bool) || continue
            regex = _regex(context, pattern)
            for (name, value) in x
                occursin(regex, string(name)) || continue
                child = _child_result(
                    context,
                    node,
                    ("patternProperties", String(pattern)),
                    value,
                    _property_path(path, name),
                    dynamic_scope,
                )
                _absorb!(result, context, child; annotations = false)
                _stopped(context, result) && return result
                tracks_coverage && push!(covered::Set{String}, String(name))
                context.annotations && _mark_property!(result, String(name))
            end
        end
    end
    if additional isa AbstractDict || additional isa Bool
        for (name, value) in x
            string(name) in (covered::Set{String}) && continue
            child = _child_result(
                context,
                node,
                ("additionalProperties",),
                value,
                _property_path(path, name),
                dynamic_scope,
            )
            _absorb!(result, context, child; annotations = false)
            _stopped(context, result) && return result
            context.annotations && _mark_property!(result, String(name))
        end
    end
    names = get(schema, "propertyNames", nothing)
    if keyword_applies(schema_dialect, "propertyNames") &&
       (names isa AbstractDict || names isa Bool)
        for name in keys(x)
            child = _child_result(
                context,
                node,
                ("propertyNames",),
                string(name),
                _property_path(path, name),
                dynamic_scope,
            )
            _absorb!(result, context, child; annotations = false)
            _stopped(context, result) && return result
        end
    end
    for keyword in ("dependencies", "dependentSchemas")
        keyword_applies(schema_dialect, keyword) || continue
        dependencies = get(schema, keyword, nothing)
        dependencies isa AbstractDict || continue
        for (name, subschema) in dependencies
            haskey(x, name) || continue
            (subschema isa AbstractDict || subschema isa Bool) || continue
            child = _child_result(
                context,
                node,
                (keyword, String(name)),
                x,
                path,
                dynamic_scope,
            )
            _absorb!(result, context, child)
            _stopped(context, result) && return result
        end
    end
    return result
end

function _object_applicators!(
    result,
    context,
    node,
    x,
    schema,
    schema_dialect,
    path,
    dynamic_scope,
)
    return result
end

function _array_item!(
    result,
    context,
    node,
    tokens,
    x,
    index,
    path,
    dynamic_scope,
)
    child = _child_result(
        context,
        node,
        tokens,
        x[index],
        _array_path(path, index),
        dynamic_scope,
    )
    _absorb!(result, context, child; annotations = false)
    context.annotations && _mark_item!(result, index)
    return result
end

function _array_applicators!(
    result,
    context,
    node,
    x::AbstractVector,
    schema::AbstractDict,
    schema_dialect::Dialect,
    path,
    dynamic_scope,
)
    prefix = get(schema, "prefixItems", nothing)
    prefix_count = 0
    if schema_dialect.modern_items && prefix isa AbstractVector
        prefix_count = min(length(prefix), length(x))
        for index in 1:prefix_count
            _array_item!(
                result,
                context,
                node,
                ("prefixItems", string(index - 1)),
                x,
                index,
                path,
                dynamic_scope,
            )
            _stopped(context, result) && return result
        end
    end
    items = get(schema, "items", nothing)
    if items isa AbstractVector && !schema_dialect.modern_items
        tuple_count = min(length(items), length(x))
        for index in 1:tuple_count
            _array_item!(
                result,
                context,
                node,
                ("items", string(index - 1)),
                x,
                index,
                path,
                dynamic_scope,
            )
            _stopped(context, result) && return result
        end
        additional = get(schema, "additionalItems", nothing)
        if additional isa AbstractDict || additional isa Bool
            for index in (tuple_count+1):length(x)
                _array_item!(
                    result,
                    context,
                    node,
                    ("additionalItems",),
                    x,
                    index,
                    path,
                    dynamic_scope,
                )
                _stopped(context, result) && return result
            end
        end
    elseif items isa AbstractDict || items isa Bool
        start = schema_dialect.modern_items ? prefix_count + 1 : 1
        for index in start:length(x)
            _array_item!(
                result,
                context,
                node,
                ("items",),
                x,
                index,
                path,
                dynamic_scope,
            )
            _stopped(context, result) && return result
        end
    end
    contains = get(schema, "contains", nothing)
    if keyword_applies(schema_dialect, "contains") &&
       (contains isa AbstractDict || contains isa Bool)
        matches = BitSet()
        for index in eachindex(x)
            child = _child_result(
                context,
                node,
                ("contains",),
                x[index],
                _array_path(path, index),
                dynamic_scope,
            )
            child.valid && push!(matches, index)
        end
        minimum =
            keyword_applies(schema_dialect, "minContains") ?
            get(schema, "minContains", 1) : 1
        maximum =
            keyword_applies(schema_dialect, "maxContains") ?
            get(schema, "maxContains", typemax(Int)) : typemax(Int)
        if !(minimum <= length(matches) <= maximum)
            _invalidate!(result, context, _issue(x, path, "contains", contains))
        else
            if context.annotations && !isempty(matches)
                result.items === nothing && (result.items = BitSet())
                union!(result.items::BitSet, matches)
            end
        end
    end
    return result
end

function _array_applicators!(
    result,
    context,
    node,
    x,
    schema,
    schema_dialect,
    path,
    dynamic_scope,
)
    return result
end

function _unevaluated!(
    result,
    context,
    node,
    x::AbstractDict,
    schema::AbstractDict,
    path,
    dynamic_scope,
)
    unevaluated = get(schema, "unevaluatedProperties", nothing)
    (unevaluated isa AbstractDict || unevaluated isa Bool) || return result
    for (name, value) in x
        result.properties !== nothing &&
            string(name) in result.properties &&
            continue
        child = _child_result(
            context,
            node,
            ("unevaluatedProperties",),
            value,
            _property_path(path, name),
            dynamic_scope,
        )
        _absorb!(result, context, child; annotations = false)
        _stopped(context, result) && return result
        _mark_property!(result, String(name))
    end
    return result
end

function _unevaluated!(
    result,
    context,
    node,
    x::AbstractVector,
    schema::AbstractDict,
    path,
    dynamic_scope,
)
    unevaluated = get(schema, "unevaluatedItems", nothing)
    (unevaluated isa AbstractDict || unevaluated isa Bool) || return result
    for index in eachindex(x)
        result.items !== nothing && index in result.items && continue
        _array_item!(
            result,
            context,
            node,
            ("unevaluatedItems",),
            x,
            index,
            path,
            dynamic_scope,
        )
        _stopped(context, result) && return result
    end
    return result
end

_unevaluated!(result, context, node, x, schema, path, dynamic_scope) = result

function _evaluate_schema(
    context::EvaluationContext,
    node::Resources.NodeId,
    x,
    schema::Bool,
    schema_dialect::Dialect,
    path::EvaluationPath,
    dynamic_scope,
)
    result = EvaluationResult()
    schema || _invalidate!(result, context, _issue(x, path, "schema", false))
    return result
end

function _evaluate_schema(
    context::EvaluationContext,
    node::Resources.NodeId,
    x,
    schema::AbstractDict,
    schema_dialect::Dialect,
    path::EvaluationPath,
    dynamic_scope,
)
    result = EvaluationResult()
    _references!(
        result,
        context,
        node,
        x,
        schema,
        schema_dialect,
        path,
        dynamic_scope,
    ) || return result
    schema_dialect.validation &&
        _simple_assertions!(result, context, x, schema, schema_dialect, path)
    _stopped(context, result) && return result
    if schema_dialect.applicator
        _combinators!(
            result,
            context,
            node,
            x,
            schema,
            schema_dialect,
            path,
            dynamic_scope,
        )
        _stopped(context, result) && return result
        _object_applicators!(
            result,
            context,
            node,
            x,
            schema,
            schema_dialect,
            path,
            dynamic_scope,
        )
        _stopped(context, result) && return result
        _array_applicators!(
            result,
            context,
            node,
            x,
            schema,
            schema_dialect,
            path,
            dynamic_scope,
        )
        _stopped(context, result) && return result
    end
    schema_dialect.unevaluated &&
        _unevaluated!(result, context, node, x, schema, path, dynamic_scope)
    return result
end

function _evaluate_compiled_node(
    context::EvaluationContext,
    compiled::CompiledNode,
    x,
    path::EvaluationPath,
    dynamic_scope::Vector{Resources.ResourceId},
)
    node = compiled.id
    context.evaluations += 1
    context.evaluations <= context.max_evaluations || throw(
        EvaluationError(
            node,
            _path_string(path),
            "the evaluation limit was reached",
        ),
    )
    context.depth += 1
    context.depth <= context.max_depth || begin
        context.depth -= 1
        throw(
            EvaluationError(
                node,
                _path_string(path),
                "the evaluation depth limit was reached",
            ),
        )
    end
    scoped = dynamic_scope
    if isempty(dynamic_scope) || last(dynamic_scope) != node.resource
        scoped = copy(dynamic_scope)
        push!(scoped, node.resource)
    end
    if !context.tracks_cycles
        try
            return _evaluate_schema(
                context,
                node,
                x,
                compiled.value,
                compiled.dialect,
                path,
                scoped,
            )
        finally
            context.depth -= 1
        end
    end
    scoped_key =
        compiled.dialect.dynamic_refs || compiled.dialect.recursive_refs ?
        Tuple(scoped) : ()
    active = (compiled.index, path, scoped_key)
    if active in context.active
        context.depth -= 1
        throw(
            EvaluationError(
                node,
                _path_string(path),
                "reference evaluation does not terminate",
            ),
        )
    end
    push!(context.active, active)
    try
        return _evaluate_schema(
            context,
            node,
            x,
            compiled.value,
            compiled.dialect,
            path,
            scoped,
        )
    finally
        delete!(context.active, active)
        context.depth -= 1
    end
end

function _evaluate_node(
    context::EvaluationContext,
    raw::Resources.NodeId,
    x,
    path::EvaluationPath,
    dynamic_scope::Vector{Resources.ResourceId},
)
    return _evaluate_compiled_node(
        context,
        _compiled_node(context.schema, raw),
        x,
        path,
        dynamic_scope,
    )
end

function validate(
    schema::CompiledSchema,
    x;
    fail_fast::Bool = true,
    max_evaluations::Integer = 1_000_000,
    max_issues::Integer = 10_000,
    max_depth::Integer = 512,
)
    context = EvaluationContext(
        schema,
        max_evaluations,
        max_issues,
        max_depth,
        !fail_fast,
    )
    result = _evaluate_node(
        context,
        schema.root,
        x,
        EvaluationPath(),
        Resources.ResourceId[schema.root.resource],
    )
    if fail_fast
        return result.valid ? nothing :
               first(result.issues::Vector{SingleIssue})
    end
    return something(result.issues, SingleIssue[])
end

Base.isvalid(schema::CompiledSchema, x) = validate(schema, x) === nothing
