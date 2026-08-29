struct Provenance
    node::Resources.NodeId
    reference_chain::Tuple{Vararg{Resources.NodeId}}
end

Provenance(object::BoundObject) = Provenance(object.node, object.reference_chain)
Provenance(node::Resources.NodeId) = Provenance(node, (node,))

mutable struct SchemaWorkspace
    compiled::Any
end

struct SchemaHandle
    node::Resources.NodeId
    value::Union{AbstractDict,Bool}
    version::DocumentVersion
    workspace::SchemaWorkspace
end

function Base.getproperty(handle::SchemaHandle, name::Symbol)
    if name === :compiled
        workspace = getfield(handle, :workspace)
        workspace.compiled === nothing && return nothing
        return SchemaEngine.select(workspace.compiled, getfield(handle, :node))
    end
    return getfield(handle, name)
end

struct NormalizedServerVariable
    name::String
    default::String
    values::Tuple{Vararg{String}}
    description::Union{Nothing,String}
end

struct NormalizedServer
    name::Union{Nothing,String}
    url::String
    description::Union{Nothing,String}
    variables::Tuple{Vararg{NormalizedServerVariable}}
    provenance::Provenance
end

struct NormalizedSecurityScheme
    name::String
    type::Symbol
    location::Union{Nothing,Symbol}
    parameter_name::Union{Nothing,String}
    scheme::Union{Nothing,String}
    bearer_format::Union{Nothing,String}
    openid_connect_url::Union{Nothing,String}
    flows::Any
    description::Union{Nothing,String}
    extensions::Resources.FrozenObject
    provenance::Provenance
end

struct NormalizedSecurityRequirement
    alternatives::Tuple{Vararg{Pair{String,Tuple{Vararg{String}}}}}
    provenance::Provenance
end

struct NormalizedEncoding
    name::String
    content_type::Union{Nothing,String}
    # This is a Tuple rather than Tuple{Vararg{NormalizedHeader}} because
    # Header Object content can contain Media Type Objects, which in turn can
    # contain Encoding Objects. The abstract field breaks that Julia type
    # declaration cycle while the normalizer still stores only
    # NormalizedHeader values.
    headers::Tuple
    # OAS 3.2 permits recursive, named Encoding Objects. Tuple breaks the
    # recursive Julia declaration while retaining immutable normalized values.
    encoding::Tuple
    style::Union{Nothing,Symbol}
    explode::Union{Nothing,Bool}
    allow_reserved::Bool
    raw::Resources.FrozenObject
    provenance::Provenance
end

struct NormalizedMediaType
    content_type::String
    schema::Union{Nothing,SchemaHandle}
    item_schema::Union{Nothing,SchemaHandle}
    encoding::Tuple{Vararg{NormalizedEncoding}}
    example::Any
    examples::Resources.FrozenObject
    raw::Resources.FrozenObject
    provenance::Provenance
end

struct NormalizedParameter
    name::String
    location::Symbol
    description::Union{Nothing,String}
    required::Bool
    deprecated::Bool
    allow_empty_value::Bool
    style::Union{Nothing,Symbol}
    explode::Union{Nothing,Bool}
    allow_reserved::Bool
    schema::Union{Nothing,SchemaHandle}
    content::Tuple{Vararg{NormalizedMediaType}}
    example::Any
    examples::Resources.FrozenObject
    extensions::Resources.FrozenObject
    provenance::Provenance
end

struct NormalizedHeader
    name::String
    description::Union{Nothing,String}
    deprecated::Bool
    required::Bool
    style::Symbol
    explode::Bool
    schema::Union{Nothing,SchemaHandle}
    content::Tuple{Vararg{NormalizedMediaType}}
    provenance::Provenance
end

struct NormalizedRequestBody
    description::Union{Nothing,String}
    required::Bool
    content::Tuple{Vararg{NormalizedMediaType}}
    extensions::Resources.FrozenObject
    provenance::Provenance
end

struct NormalizedResponse
    selector::String
    summary::Union{Nothing,String}
    description::Union{Nothing,String}
    headers::Tuple{Vararg{NormalizedHeader}}
    content::Tuple{Vararg{NormalizedMediaType}}
    links::Resources.FrozenObject
    extensions::Resources.FrozenObject
    provenance::Provenance
end

struct NormalizedOperation
    id::String
    method::Symbol
    path::String
    direction::Symbol
    summary::Union{Nothing,String}
    description::Union{Nothing,String}
    tags::Tuple{Vararg{String}}
    deprecated::Bool
    parameters::Tuple{Vararg{NormalizedParameter}}
    request_body::Union{Nothing,NormalizedRequestBody}
    responses::Tuple{Vararg{NormalizedResponse}}
    security::Tuple{Vararg{NormalizedSecurityRequirement}}
    servers::Tuple{Vararg{NormalizedServer}}
    callbacks::Resources.FrozenObject
    extensions::Resources.FrozenObject
    provenance::Provenance
end

struct NormalizedAPI
    source::SourceDocument
    registry::Resources.FrozenRegistry
    title::String
    api_version::String
    description::Union{Nothing,String}
    servers::Tuple{Vararg{NormalizedServer}}
    security_schemes::Tuple{Vararg{NormalizedSecurityScheme}}
    security::Tuple{Vararg{NormalizedSecurityRequirement}}
    schemas::Tuple{Vararg{Pair{String,SchemaHandle}}}
    operations::Tuple{Vararg{NormalizedOperation}}
    extensions::Resources.FrozenObject
    diagnostics::Tuple{Vararg{Diagnostic}}
end

mutable struct NormalizationContext
    resolver::ResolverContext
    schema_workspace::SchemaWorkspace
    schema_cache::Dict{Resources.NodeId,SchemaHandle}
    operation_ids::Dict{String,Resources.NodeId}
    callback_operations::Vector{NormalizedOperation}
end

_frozen_empty() = Resources.freeze(JSON.Object{String,Any}())

function _raw_object(value)
    value isa AbstractDict || return _frozen_empty()
    return Resources.freeze(value)
end

function _extensions(value)
    output = JSON.Object{String,Any}()
    value isa AbstractDict || return Resources.freeze(output)
    for (key, item) in value
        startswith(lowercase(String(key)), "x-") || continue
        output[String(key)] = item
    end
    return Resources.freeze(output)
end

_optional_string(value, key) = get(value, key, nothing) isa AbstractString ?
                               String(value[key]) : nothing

function _schema_handle!(
    context::NormalizationContext,
    value,
    node::Resources.NodeId,
)
    (value isa AbstractDict || value isa Bool) || begin
        _reference_error!(
            context.resolver,
            :schema_type,
            "Schema Object must be an object or boolean schema",
            node,
        )
        return nothing
    end
    cached = get(context.schema_cache, node, nothing)
    cached === nothing || return cached
    version = _resource_version(context.resolver, node.resource)
    handle = SchemaHandle(node, value, version, context.schema_workspace)
    context.schema_cache[node] = handle
    return handle
end

function _schema_dialect(context::NormalizationContext, handle::SchemaHandle)
    handle.version.minor == 0 && return SchemaEngine.DRAFT4
    resource = Resources.resource(context.resolver.registry, handle.node.resource)
    declared = resource.contents isa AbstractDict ?
               get(resource.contents, "jsonSchemaDialect", nothing) : nothing
    if declared isa AbstractString
        normalized = rstrip(String(declared), '#')
        if startswith(normalized, "https://spec.openapis.org/oas/3.1/dialect/") ||
           startswith(normalized, "https://spec.openapis.org/oas/3.2/dialect/")
            return SchemaEngine.DRAFT202012
        end
        return normalized
    end
    return SchemaEngine.DRAFT202012
end

function _oas_dialect_aliases(resources)
    aliases = Dict{String,SchemaEngine.Dialect}()
    function visit(value)
        if value isa AbstractDict
            for key in ("\$schema", "jsonSchemaDialect")
                declared = get(value, key, nothing)
                declared isa AbstractString || continue
                normalized = rstrip(String(declared), '#')
                if startswith(normalized, "https://spec.openapis.org/oas/3.1/dialect/") ||
                   startswith(normalized, "https://spec.openapis.org/oas/3.2/dialect/")
                    aliases[normalized] = SchemaEngine.DRAFT202012
                end
            end
            foreach(visit, values(value))
        elseif value isa AbstractVector
            foreach(visit, value)
        end
        return
    end
    for resource in resources
        visit(resource.contents)
    end
    return aliases
end

function _json_copy(value)
    if value isa AbstractDict
        output = JSON.Object{String,Any}()
        sizehint!(output, length(value))
        for (key, child) in value
            output[String(key)] = _json_copy(child)
        end
        return output
    elseif value isa AbstractVector
        return Any[_json_copy(child) for child in value]
    end
    return value
end

const OAS30_SINGLE_SCHEMA_KEYWORDS = (
    "not",
    "items",
    "additionalProperties",
    "additionalItems",
    "propertyNames",
    "contains",
)
const OAS30_ARRAY_SCHEMA_KEYWORDS = ("allOf", "anyOf", "oneOf")
const OAS30_MAP_SCHEMA_KEYWORDS = (
    "properties",
    "patternProperties",
    "definitions",
)
const OAS30_ANNOTATION_KEYWORDS = Set([
    "title",
    "description",
    "default",
    "example",
    "deprecated",
    "readOnly",
    "writeOnly",
    "xml",
    "externalDocs",
    "discriminator",
])

"""Translate only OAS 3.0 Schema Objects to their Draft 4 equivalent."""
function _oas30_schema_compat(
    value;
    permissive_nullable::Bool = false,
    legacy_nullable::Base.RefValue{Bool} = Ref(false),
)
    value isa AbstractDict || return _json_copy(value)
    output = _json_copy(value)
    nullable = get(value, "nullable", false) === true
    type = get(value, "type", nothing)
    nullable && type isa AbstractString &&
        (output["type"] = Any[String(type), "null"])

    for keyword in OAS30_SINGLE_SCHEMA_KEYWORDS
        child = get(value, keyword, nothing)
        (child isa AbstractDict || child isa Bool) || continue
        output[keyword] = _oas30_schema_compat(
            child;
            permissive_nullable,
            legacy_nullable,
        )
    end
    for keyword in OAS30_ARRAY_SCHEMA_KEYWORDS
        children = get(value, keyword, nothing)
        children isa AbstractVector || continue
        output[keyword] = Any[
            (child isa AbstractDict || child isa Bool) ?
            _oas30_schema_compat(
                child;
                permissive_nullable,
                legacy_nullable,
            ) : _json_copy(child) for child in children
        ]
    end
    for keyword in OAS30_MAP_SCHEMA_KEYWORDS
        children = get(value, keyword, nothing)
        children isa AbstractDict || continue
        mapped = JSON.Object{String,Any}()
        for (name, child) in children
            mapped[String(name)] =
                (child isa AbstractDict || child isa Bool) ?
                _oas30_schema_compat(
                    child;
                    permissive_nullable,
                    legacy_nullable,
                ) : _json_copy(child)
        end
        output[keyword] = mapped
    end
    dependencies = get(value, "dependencies", nothing)
    if dependencies isa AbstractDict
        mapped = JSON.Object{String,Any}()
        for (name, child) in dependencies
            mapped[String(name)] = child isa AbstractDict || child isa Bool ?
                                   _oas30_schema_compat(
                child;
                permissive_nullable,
                legacy_nullable,
            ) : _json_copy(child)
        end
        output["dependencies"] = mapped
    end
    if nullable && type === nothing && permissive_nullable
        legacy_nullable[] = true
        assertion = _json_copy(output)
        delete!(assertion, "nullable")
        wrapped = JSON.Object{String,Any}()
        for (key, child) in output
            name = String(key)
            if name in OAS30_ANNOTATION_KEYWORDS || startswith(lowercase(name), "x-")
                wrapped[name] = _json_copy(child)
                delete!(assertion, name)
            end
        end
        null_schema = JSON.Object{String,Any}()
        null_schema["type"] = "null"
        wrapped["anyOf"] = Any[assertion, null_schema]
        return wrapped
    end
    return output
end

function _oas30_schema_roots!(context::NormalizationContext)
    roots = Set(
        handle.node for handle in values(context.schema_cache) if
        handle.version.minor == 0
    )
    queue = collect(roots)
    scanned = Set{Resources.NodeId}()
    index = 1
    while index <= length(queue)
        node = queue[index]
        index += 1
        node in scanned && continue
        push!(scanned, node)
        resource = Resources.resource(context.resolver.registry, node.resource)
        value = try
            Resources.resolve(resource.contents, node.pointer)
        catch
            continue
        end
        value isa AbstractDict || continue
        reference = get(value, "\$ref", nothing)
        if reference isa AbstractString
            resolved = try
                _resolve_reference!(context.resolver, node, reference)
            catch
                nothing
            end
            if resolved !== nothing &&
               (resolved.value isa AbstractDict || resolved.value isa Bool)
                push!(roots, resolved.id)
                push!(queue, resolved.id)
            end
            continue
        end
        for keyword in OAS30_SINGLE_SCHEMA_KEYWORDS
            child = get(value, keyword, nothing)
            (child isa AbstractDict || child isa Bool) || continue
            push!(queue, _childnode(node, keyword))
        end
        for keyword in OAS30_ARRAY_SCHEMA_KEYWORDS
            children = get(value, keyword, nothing)
            children isa AbstractVector || continue
            for (child_index, child) in enumerate(children)
                (child isa AbstractDict || child isa Bool) || continue
                push!(
                    queue,
                    _childnode(_childnode(node, keyword), string(child_index - 1)),
                )
            end
        end
        for keyword in OAS30_MAP_SCHEMA_KEYWORDS
            children = get(value, keyword, nothing)
            children isa AbstractDict || continue
            for (name, child) in children
                (child isa AbstractDict || child isa Bool) || continue
                push!(queue, _childnode(_childnode(node, keyword), String(name)))
            end
        end
        dependencies = get(value, "dependencies", nothing)
        if dependencies isa AbstractDict
            for (name, child) in dependencies
                (child isa AbstractDict || child isa Bool) || continue
                push!(
                    queue,
                    _childnode(_childnode(node, "dependencies"), String(name)),
                )
            end
        end
    end
    return roots
end

function _replace_pointer(document, pointer::Resources.JSONPointer, value)
    isempty(pointer) && return value
    parent_pointer = Resources.JSONPointer(Base.front(pointer.tokens))
    parent = Resources.resolve(document, parent_pointer)
    token = pointer.tokens[end]
    if parent isa AbstractDict
        parent[token] = value
    else
        parent[Base.parse(Int, token) + 1] = value
    end
    return document
end

function _schema_resources(context::NormalizationContext)
    roots = _oas30_schema_roots!(context)
    resources = collect(values(getfield(context.resolver.registry, :resources)))
    return Resources.Resource[
        if _resource_version(context.resolver, resource.id).minor == 0
            contents = _json_copy(resource.contents)
            resource_roots = sort(
                [
                    node for node in roots if Resources.resource(
                        context.resolver.registry,
                        node.resource,
                    ).id == resource.id
                ];
                by = node -> -length(node.pointer),
            )
            for node in resource_roots
                schema = try
                    Resources.resolve(contents, node.pointer)
                catch
                    continue
                end
                legacy_nullable = Ref(false)
                contents = _replace_pointer(
                    contents,
                    node.pointer,
                    _oas30_schema_compat(
                        schema;
                        permissive_nullable = !context.resolver.strict,
                        legacy_nullable,
                    ),
                )
                legacy_nullable[] && _warning!(
                    context.resolver.bag,
                    :legacy_nullable_without_type,
                    "OAS 3.0 nullable has no normative effect without type in the same Schema Object; permissive mode treats it as accepting null",
                    SourceLocation(node.resource, node.pointer),
                )
            end
            Resources.Resource(
                resource.id,
                contents;
                retrieval = resource.retrieval,
                source = resource.source,
                media_type = resource.media_type,
            )
        else
            resource
        end for resource in resources
    ]
end

function _canonical_json!(io::IO, value)
    if value isa AbstractDict
        print(io, '{')
        names = sort!(String[String(key) for key in keys(value)])
        for (index, name) in enumerate(names)
            index == 1 || print(io, ',')
            print(io, JSON.json(name), ':')
            _canonical_json!(io, value[name])
        end
        print(io, '}')
    elseif value isa AbstractVector
        print(io, '[')
        for (index, child) in enumerate(value)
            index == 1 || print(io, ',')
            _canonical_json!(io, child)
        end
        print(io, ']')
    else
        print(io, JSON.json(value))
    end
    return io
end

function _content_digest(value)
    io = IOBuffer()
    _canonical_json!(io, value)
    return bytes2hex(SHA.sha256(take!(io)))
end

function _schema_source_node(registry, node::Resources.NodeId)
    resource = Resources.resource(registry, node.resource)
    pointer = resource.source.pointer
    for token in node.pointer
        pointer /= token
    end
    return Resources.NodeId(resource.source.resource, pointer)
end

function _top_schema_resource(registry, id::Resources.ResourceId)
    resource = Resources.resource(registry, id)
    return Resources.resource(registry, resource.source.resource)
end

function _portable_schema_ids(context::NormalizationContext, schemas)
    template = getfield(schemas, :template)
    registry = template.registry
    resources = collect(values(getfield(registry, :resources)))
    top = unique(
        resource -> resource.id,
        Resources.Resource[
            _top_schema_resource(registry, resource.id) for resource in resources
        ],
    )
    primary = _top_schema_resource(
        registry,
        context.resolver.root.resource.retrieval,
    )
    labels = Dict{Resources.ResourceId,String}(
        primary.id => "root-" * first(_content_digest(primary.contents), 20),
    )

    references = collect(getfield(template, :references))
    while true
        candidates = Tuple{String,String,String,Resources.ResourceId}[]
        for ((node, keyword), target) in references
            source = _schema_source_node(registry, node)
            source_top = _top_schema_resource(registry, source.resource)
            target_top = _top_schema_resource(registry, target.resource)
            haskey(labels, source_top.id) || continue
            haskey(labels, target_top.id) && continue
            push!(
                candidates,
                (
                    labels[source_top.id],
                    string(source.pointer),
                    keyword,
                    target_top.id,
                ),
            )
        end
        isempty(candidates) && break
        sort!(candidates; by = item -> (item[1], item[2], item[3]))
        progressed = false
        for (parent, pointer, keyword, target) in candidates
            haskey(labels, target) && continue
            seed = parent * "|" * pointer * "|" * keyword
            labels[target] = "external-" * first(bytes2hex(SHA.sha256(seed)), 20)
            progressed = true
        end
        progressed || break
    end

    remaining = sort(
        [resource for resource in top if !haskey(labels, resource.id)];
        by = resource -> (_content_digest(resource.contents), string(resource.id)),
    )
    used = Set(values(labels))
    for resource in remaining
        base = "resource-" * first(_content_digest(resource.contents), 20)
        label = base
        suffix = 2
        while label in used
            label = base * "-" * string(suffix)
            suffix += 1
        end
        labels[resource.id] = label
        push!(used, label)
    end

    output = Dict{Resources.ResourceId,Resources.ResourceId}()
    for resource in resources
        owner = _top_schema_resource(registry, resource.id)
        label = labels[owner.id]
        if resource.id == owner.id
            uri = "https://openapi.invalid/schema/" * label * ".json"
        else
            pointer = string(resource.source.pointer)
            suffix = first(bytes2hex(SHA.sha256(pointer)), 20)
            uri = "https://openapi.invalid/schema/" * label * "/" * suffix * ".json"
        end
        output[resource.id] = Resources.ResourceId(uri)
    end
    return output
end

function _compile_schemas!(context::NormalizationContext)
    isempty(context.schema_cache) && return
    handles = sort(
        collect(values(context.schema_cache));
        by = handle -> (string(handle.node.resource), string(handle.node.pointer)),
    )
    roots = Resources.NodeId[handle.node for handle in handles]
    root_dialects = Dict(
        handle.node => _schema_dialect(context, handle) for handle in handles
    )
    resources = _schema_resources(context)
    dialect_aliases = _oas_dialect_aliases(resources)
    compiled = try
        SchemaEngine.CompiledSchemas(
            resources,
            roots;
            dialect = SchemaEngine.DRAFT202012,
            root_dialects,
            dialect_aliases,
            retriever = _schema_retriever(context.resolver),
            max_resources = context.resolver.max_resources,
            max_nodes = context.resolver.max_nodes,
            max_depth = context.resolver.max_depth,
        )
    catch error
        location = error isa SchemaEngine.CompilationError ? error.location : first(roots)
        _reference_error!(
            context.resolver,
            :invalid_schema,
            sprint(showerror, error),
            location,
        )
        return
    end
    context.schema_workspace.compiled = try
        SchemaEngine.rebase(compiled, _portable_schema_ids(context, compiled))
    catch error
        location = error isa SchemaEngine.CompilationError ? error.location : first(roots)
        _reference_error!(
            context.resolver,
            :invalid_schema_rebase,
            "cannot create a portable schema graph: $(sprint(showerror, error))",
            location,
        )
        return
    end
    return
end

function _normalize_servers!(context::NormalizationContext, value, node)
    value === nothing && return NormalizedServer[]
    output = NormalizedServer[]
    names = Set{String}()
    for (index, raw) in enumerate(value)
        itemnode = _childnode(node, string(index - 1))
        object = _bind_object!(context.resolver, raw, itemnode, :server)
        object === nothing && continue
        url = get(object.value, "url", nothing)
        url isa AbstractString || continue
        name = _optional_string(object.value, "name")
        if name !== nothing
            name in names && _reference_error!(
                context.resolver,
                :duplicate_server_name,
                "server name $(repr(name)) is not unique in this server list",
                object.node,
            )
            push!(names, name)
        end
        variables = NormalizedServerVariable[]
        raw_variables = get(object.value, "variables", nothing)
        if raw_variables isa AbstractDict
            variable_node = fieldnode(object, "variables")
            for (name, raw_variable) in raw_variables
                raw_variable isa AbstractDict || continue
                default = get(raw_variable, "default", nothing)
                default isa AbstractString || continue
                values = get(raw_variable, "enum", String[])
                normalized_values = Tuple(String(item) for item in values)
                String(default) in normalized_values || isempty(normalized_values) ||
                    _reference_error!(
                        context.resolver,
                        :server_variable_default,
                        "server variable $(repr(name)) default is not in its enum",
                        _childnode(variable_node, String(name)),
                    )
                push!(
                    variables,
                    NormalizedServerVariable(
                        String(name),
                        String(default),
                        normalized_values,
                        _optional_string(raw_variable, "description"),
                    ),
                )
            end
        end
        placeholders = Set(
            String(captures[1]) for captures in
            eachmatch(r"\{([^{}]+)\}", String(url))
        )
        defined = Set(variable.name for variable in variables)
        for missing in setdiff(placeholders, defined)
            _reference_error!(
                context.resolver,
                :missing_server_variable,
                "server URL variable $(repr(missing)) has no definition",
                object.node,
            )
        end
        for unused in setdiff(defined, placeholders)
            _warning!(
                context.resolver.bag,
                :unused_server_variable,
                "server variable $(repr(unused)) is not present in the URL template",
                SourceLocation(object.node.resource, object.node.pointer),
            )
        end
        expanded = String(url)
        for variable in variables
            expanded = replace(
                expanded,
                "{" * variable.name * "}" => variable.default,
            )
        end
        parsed = try
            Resources.URIs.URI(expanded)
        catch error
            _reference_error!(
                context.resolver,
                :invalid_server_url,
                "invalid server URL: $(sprint(showerror, error))",
                object.node,
            )
            nothing
        end
        if parsed !== nothing && (!isempty(parsed.query) || !isempty(parsed.fragment))
            _reference_error!(
                context.resolver,
                :invalid_server_url,
                "server URL must not contain a query or fragment",
                object.node,
            )
        end
        push!(
            output,
            NormalizedServer(
                name,
                String(url),
                _optional_string(object.value, "description"),
                Tuple(variables),
                Provenance(object),
            ),
        )
    end
    return output
end

function _normalize_security_scheme!(context, name, raw, node)
    object = _bind_object!(context.resolver, raw, node, :security_scheme)
    object === nothing && return nothing
    raw_type = get(object.value, "type", nothing)
    raw_type isa AbstractString || return nothing
    type = Symbol(replace(lowercase(String(raw_type)), "-" => "_"))
    raw_location = _optional_string(object.value, "in")
    location = raw_location === nothing ? nothing : Symbol(raw_location)
    return NormalizedSecurityScheme(
        String(name),
        type,
        location,
        _optional_string(object.value, "name"),
        _optional_string(object.value, "scheme"),
        _optional_string(object.value, "bearerFormat"),
        _optional_string(object.value, "openIdConnectUrl"),
        get(object.value, "flows", nothing),
        _optional_string(object.value, "description"),
        _extensions(object.value),
        Provenance(object),
    )
end

function _normalize_security_schemes!(context::NormalizationContext, value, node)
    output = NormalizedSecurityScheme[]
    value isa AbstractDict || return output
    for (name, raw) in value
        itemnode = _childnode(node, String(name))
        scheme = _normalize_security_scheme!(context, name, raw, itemnode)
        scheme === nothing || push!(output, scheme)
    end
    return output
end

function _normalize_security!(context::NormalizationContext, value, node)
    value === nothing && return NormalizedSecurityRequirement[]
    output = NormalizedSecurityRequirement[]
    for (index, raw) in enumerate(value)
        itemnode = _childnode(node, string(index - 1))
        raw isa AbstractDict || continue
        alternatives = Pair{String,Tuple{Vararg{String}}}[]
        for (name, scopes) in raw
            push!(alternatives, String(name) => Tuple(String(scope) for scope in scopes))
        end
        push!(
            output,
            NormalizedSecurityRequirement(Tuple(alternatives), Provenance(itemnode)),
        )
    end
    return output
end

function _default_style(location::Symbol)
    location === :query && return :form
    location === :querystring && return nothing
    location === :cookie && return :form
    return :simple
end

function _default_explode(style)
    style === nothing && return nothing
    return style in (:form, :cookie)
end

function _normalize_encoding!(context::NormalizationContext, value, node)
    output = NormalizedEncoding[]
    value isa AbstractDict || return output
    for (name, raw) in value
        itemnode = _childnode(node, String(name))
        raw isa AbstractDict || continue
        raw_style = _optional_string(raw, "style")
        style = raw_style === nothing ? nothing : Symbol(raw_style)
        headers = NormalizedHeader[]
        raw_headers = get(raw, "headers", nothing)
        if raw_headers isa AbstractDict
            headernode = _childnode(itemnode, "headers")
            seen = Set{String}()
            for (header_name, raw_header) in raw_headers
                lowered = lowercase(String(header_name))
                if lowered == "content-type"
                    _warning!(
                        context.resolver.bag,
                        :ignored_content_type_header,
                        "encoding header `Content-Type` is defined by `contentType` and is ignored",
                        SourceLocation(
                            itemnode.resource,
                            _childnode(headernode, String(header_name)).pointer,
                        ),
                    )
                    continue
                end
                lowered in seen && _reference_error!(
                    context.resolver,
                    :duplicate_header,
                    "encoding header $(repr(header_name)) duplicates a case-insensitive name",
                    _childnode(headernode, String(header_name)),
                )
                push!(seen, lowered)
                header = _normalize_header!(
                    context,
                    header_name,
                    raw_header,
                    _childnode(headernode, String(header_name)),
                )
                header === nothing || push!(headers, header)
            end
        end
        push!(
            output,
            NormalizedEncoding(
                String(name),
                _optional_string(raw, "contentType"),
                Tuple(headers),
                Tuple(
                    _normalize_encoding!(
                        context,
                        get(raw, "encoding", nothing),
                        _childnode(itemnode, "encoding"),
                    ),
                ),
                style,
                get(raw, "explode", nothing),
                get(raw, "allowReserved", false) === true,
                _raw_object(raw),
                Provenance(itemnode),
            ),
        )
    end
    return output
end

const MEDIA_TYPE_TOKEN = raw"[!#$%&'*+.^_`|~0-9A-Za-z-]+"

function _valid_media_type_key(value::AbstractString)
    base = strip(first(split(String(value), ';'; limit = 2)))
    matched = match(
        Regex("^(\\*|" * MEDIA_TYPE_TOKEN * ")/(\\*|\\*\\+" *
              MEDIA_TYPE_TOKEN * "|" * MEDIA_TYPE_TOKEN * ")\$"),
        base,
    )
    matched === nothing && return false
    matched.captures[1] == "*" && return matched.captures[2] == "*"
    return true
end

function _normalized_encoding_content_type(content_type)
    content_type === nothing && return ""
    selected = strip(first(split(String(content_type), ','; limit = 2)))
    return lowercase(strip(first(split(selected, ';'; limit = 2))))
end

function _check_encoding_scope!(context, encodings, base_media_type)
    if startswith(base_media_type, "multipart/") &&
       base_media_type != "multipart/form-data"
        for encoding in encodings
            if encoding.style !== nothing ||
               encoding.explode !== nothing ||
               haskey(encoding.raw, "allowReserved")
                _warning!(
                    context.resolver.bag,
                    :ignored_non_form_multipart_encoding_style,
                    "encoding style, explode, and allowReserved fields are ignored for multipart media types other than multipart/form-data",
                    SourceLocation(
                        encoding.provenance.node.resource,
                        encoding.provenance.node.pointer,
                    ),
                )
            end
        end
    elseif base_media_type == "application/x-www-form-urlencoded"
        for encoding in encodings
            isempty(encoding.headers) && continue
            _warning!(
                context.resolver.bag,
                :ignored_form_encoding_headers,
                "application/x-www-form-urlencoded encoding headers are ignored",
                SourceLocation(
                    encoding.provenance.node.resource,
                    encoding.provenance.node.pointer,
                ),
            )
        end
    end
    for encoding in encodings
        isempty(encoding.encoding) && continue
        _check_encoding_scope!(
            context,
            encoding.encoding,
            _normalized_encoding_content_type(encoding.content_type),
        )
    end
    return
end

function _normalize_content!(context::NormalizationContext, value, node)
    output = NormalizedMediaType[]
    value isa AbstractDict || return output
    seen = Set{String}()
    for (content_type, raw) in value
        itemnode = _childnode(node, String(content_type))
        _valid_media_type_key(String(content_type)) || _reference_error!(
            context.resolver,
            :invalid_media_type,
            "content key $(repr(content_type)) is not a valid media type or media range",
            itemnode,
        )
        # Keys differing only in parameters are distinct entries — deployed
        # specs use them (Kubernetes documents `application/json` next to
        # `application/json;stream=watch`) — so compare the whole key.
        normalized_content_type = lowercase(strip(String(content_type)))
        normalized_content_type in seen && _reference_error!(
            context.resolver,
            :duplicate_media_type,
            "content key $(repr(content_type)) duplicates a case-insensitive media type",
            itemnode,
        )
        push!(seen, normalized_content_type)
        object = _bind_object!(context.resolver, raw, itemnode, :media_type)
        object === nothing && continue
        schema = haskey(object.value, "schema") ?
                 _schema_handle!(
            context,
            object.value["schema"],
            fieldnode(object, "schema"),
        ) :
                 nothing
        item_schema = haskey(object.value, "itemSchema") ?
                      _schema_handle!(
            context,
            object.value["itemSchema"],
            fieldnode(object, "itemSchema"),
        ) : nothing
        base_media_type = lowercase(strip(first(split(String(content_type), ';'; limit = 2))))
        encodings = _normalize_encoding!(
            context,
            get(object.value, "encoding", nothing),
            fieldnode(object, "encoding"),
        )
        supports_named_encoding =
            base_media_type == "application/x-www-form-urlencoded" ||
            startswith(base_media_type, "multipart/")
        if !supports_named_encoding && !isempty(encodings)
            _warning!(
                context.resolver.bag,
                :ignored_media_encoding,
                "the encoding field is ignored for media type $(repr(content_type))",
                SourceLocation(object.node.resource, object.node.pointer),
            )
            empty!(encodings)
        else
            _check_encoding_scope!(context, encodings, base_media_type)
        end
        push!(
            output,
            NormalizedMediaType(
                String(content_type),
                schema,
                item_schema,
                Tuple(encodings),
                get(object.value, "example", nothing),
                _raw_object(get(object.value, "examples", nothing)),
                _raw_object(object.value),
                Provenance(object),
            ),
        )
    end
    return output
end

function _normalize_parameter!(context::NormalizationContext, raw, node)
    object = _bind_object!(context.resolver, raw, node, :parameter)
    object === nothing && return nothing
    name = get(object.value, "name", nothing)
    raw_location = get(object.value, "in", nothing)
    (name isa AbstractString && raw_location isa AbstractString) || return nothing
    location = Symbol(raw_location)
    if location === :header &&
       lowercase(String(name)) in ("accept", "content-type", "authorization")
        _warning!(
            context.resolver.bag,
            :ignored_header_parameter,
            "header parameter $(repr(name)) is reserved by OpenAPI and is ignored",
            SourceLocation(object.node.resource, object.node.pointer),
        )
        return nothing
    end
    required = get(object.value, "required", false) === true
    if location === :path && !required
        _reference_error!(
            context.resolver,
            :path_parameter_required,
            "path parameter $(repr(name)) must set `required: true`",
            object.node,
        )
        required = true
    end
    raw_style = _optional_string(object.value, "style")
    style = raw_style === nothing ? _default_style(location) : Symbol(raw_style)
    explode = get(object.value, "explode", nothing)
    explode === nothing && (explode = _default_explode(style))
    allowed_styles = if location === :path
        (:matrix, :label, :simple)
    elseif location === :query
        (:form, :spaceDelimited, :pipeDelimited, :deepObject)
    elseif location === :header
        (:simple,)
    elseif location === :cookie
        version = _resource_version(context.resolver, object.node.resource)
        version.minor >= 2 ? (:form, :cookie) : (:form,)
    elseif location === :querystring
        ()
    else
        ()
    end
    if style !== nothing && !(style in allowed_styles)
        _reference_error!(
            context.resolver,
            :parameter_style,
            "style $(repr(style)) is not valid for a $(location) parameter",
            object.node,
        )
    end
    schema = haskey(object.value, "schema") ?
             _schema_handle!(
        context,
        object.value["schema"],
        fieldnode(object, "schema"),
    ) : nothing
    content = Tuple(
        _normalize_content!(
            context,
            get(object.value, "content", nothing),
            fieldnode(object, "content"),
        ),
    )
    if (schema === nothing) == isempty(content)
        _reference_error!(
            context.resolver,
            :parameter_shape,
            "parameter $(repr(name)) must define exactly one of `schema` or `content`",
            object.node,
        )
    end
    length(content) <= 1 || _reference_error!(
        context.resolver,
        :parameter_content_count,
        "parameter `content` must contain exactly one media type",
        fieldnode(object, "content"),
    )
    return NormalizedParameter(
        String(name),
        location,
        _optional_string(object.value, "description"),
        required,
        get(object.value, "deprecated", false) === true,
        get(object.value, "allowEmptyValue", false) === true,
        style,
        explode,
        get(object.value, "allowReserved", false) === true,
        schema,
        content,
        get(object.value, "example", nothing),
        _raw_object(get(object.value, "examples", nothing)),
        _extensions(object.value),
        Provenance(object),
    )
end

function _parameter_key(parameter::NormalizedParameter)
    name = parameter.location === :header ? lowercase(parameter.name) : parameter.name
    return (name, parameter.location)
end

function _normalize_parameters!(context::NormalizationContext, value, node)
    output = NormalizedParameter[]
    seen = Dict{Tuple{String,Symbol},Int}()
    value === nothing && return output
    for (index, raw) in enumerate(value)
        itemnode = _childnode(node, string(index - 1))
        parameter = _normalize_parameter!(context, raw, itemnode)
        parameter === nothing && continue
        key = _parameter_key(parameter)
        if haskey(seen, key)
            _reference_error!(
                context.resolver,
                :duplicate_parameter,
                "duplicate parameter $(repr(parameter.name)) in $(parameter.location)",
                itemnode,
            )
            continue
        end
        seen[key] = length(output) + 1
        push!(output, parameter)
    end
    return output
end

function _merge_parameters(path_parameters, operation_parameters)
    output = copy(path_parameters)
    positions = Dict(_parameter_key(item) => index for (index, item) in enumerate(output))
    for item in operation_parameters
        key = _parameter_key(item)
        position = get(positions, key, 0)
        if position == 0
            push!(output, item)
            positions[key] = length(output)
        else
            output[position] = item
        end
    end
    return output
end

function _normalize_header!(context::NormalizationContext, name, raw, node)
    object = _bind_object!(context.resolver, raw, node, :header)
    object === nothing && return nothing
    raw_style = _optional_string(object.value, "style")
    style = raw_style === nothing ? :simple : Symbol(raw_style)
    explode = get(object.value, "explode", style === :form)
    schema = haskey(object.value, "schema") ?
             _schema_handle!(
        context,
        object.value["schema"],
        fieldnode(object, "schema"),
    ) : nothing
    content = Tuple(
        _normalize_content!(
            context,
            get(object.value, "content", nothing),
            fieldnode(object, "content"),
        ),
    )
    if (schema === nothing) == isempty(content)
        _reference_error!(
            context.resolver,
            :header_shape,
            "header $(repr(name)) must define exactly one of `schema` or `content`",
            object.node,
        )
    end
    length(content) <= 1 || _reference_error!(
        context.resolver,
        :header_content_count,
        "header `content` must contain exactly one media type",
        fieldnode(object, "content"),
    )
    style === :simple || _reference_error!(
        context.resolver,
        :header_style,
        "header style must be `simple`",
        object.node,
    )
    return NormalizedHeader(
        String(name),
        _optional_string(object.value, "description"),
        get(object.value, "deprecated", false) === true,
        get(object.value, "required", false) === true,
        style,
        explode === true,
        schema,
        content,
        Provenance(object),
    )
end

function _normalize_request_body!(context::NormalizationContext, raw, node)
    object = _bind_object!(context.resolver, raw, node, :request_body)
    object === nothing && return nothing
    content = Tuple(
        _normalize_content!(
            context,
            get(object.value, "content", nothing),
            fieldnode(object, "content"),
        ),
    )
    return NormalizedRequestBody(
        _optional_string(object.value, "description"),
        get(object.value, "required", false) === true,
        content,
        _extensions(object.value),
        Provenance(object),
    )
end

function _normalize_response!(context::NormalizationContext, selector, raw, node)
    object = _bind_object!(context.resolver, raw, node, :response)
    object === nothing && return nothing
    headers = NormalizedHeader[]
    raw_headers = get(object.value, "headers", nothing)
    if raw_headers isa AbstractDict
        headernode = fieldnode(object, "headers")
        seen = Set{String}()
        for (name, raw_header) in raw_headers
            lowered = lowercase(String(name))
            if lowered == "content-type"
                _warning!(
                    context.resolver.bag,
                    :ignored_content_type_header,
                    "response header `Content-Type` is defined by the response content map and is ignored",
                    SourceLocation(
                        object.node.resource,
                        _childnode(headernode, String(name)).pointer,
                    ),
                )
                continue
            end
            lowered in seen && _reference_error!(
                context.resolver,
                :duplicate_header,
                "response header names are case-insensitive and $(repr(name)) is duplicated",
                _childnode(headernode, String(name)),
            )
            push!(seen, lowered)
            header = _normalize_header!(
                context,
                name,
                raw_header,
                _childnode(headernode, String(name)),
            )
            header === nothing || push!(headers, header)
        end
    end
    return NormalizedResponse(
        String(selector),
        _optional_string(object.value, "summary"),
        _optional_string(object.value, "description"),
        Tuple(headers),
        Tuple(
            _normalize_content!(
                context,
                get(object.value, "content", nothing),
                fieldnode(object, "content"),
            ),
        ),
        _raw_object(get(object.value, "links", nothing)),
        _extensions(object.value),
        Provenance(object),
    )
end

function _normalize_responses!(context::NormalizationContext, value, node)
    output = NormalizedResponse[]
    value isa AbstractDict || begin
        version = _resource_version(context.resolver, node.resource)
        version.minor < 2 && _reference_error!(
            context.resolver,
            :missing_responses,
            "Operation Object must contain a `responses` object",
            node,
        )
        return output
    end
    seen = Set{String}()
    for (selector, raw) in value
        startswith(lowercase(String(selector)), "x-") && continue
        normalized = uppercase(String(selector))
        valid = lowercase(normalized) == "default" ||
                occursin(r"^[1-5][0-9][0-9]$", normalized) ||
                occursin(r"^[1-5]XX$", normalized)
        valid || _reference_error!(
            context.resolver,
            :invalid_response_selector,
            "invalid response selector $(repr(selector))",
            _childnode(node, String(selector)),
        )
        normalized in seen && _reference_error!(
            context.resolver,
            :duplicate_response_selector,
            "duplicate response selector $(repr(selector))",
            _childnode(node, String(selector)),
        )
        push!(seen, normalized)
        response = _normalize_response!(
            context,
            selector,
            raw,
            _childnode(node, String(selector)),
        )
        response === nothing || push!(output, response)
    end
    isempty(seen) && _reference_error!(
        context.resolver,
        :empty_responses,
        "Responses Object must contain at least one response selector",
        node,
    )
    return output
end

function _path_parameters!(context, path, parameters, node)
    captures = String[String(match.captures[1]) for match in eachmatch(r"\{([^{}]+)\}", path)]
    defined = String[
        parameter.name for parameter in parameters if parameter.location === :path
    ]
    for missing in setdiff(captures, defined)
        _reference_error!(
            context.resolver,
            :missing_path_parameter,
            "path template parameter $(repr(missing)) has no matching path parameter",
            node,
        )
    end
    for unused in setdiff(defined, captures)
        _reference_error!(
            context.resolver,
            :unused_path_parameter,
            "path parameter $(repr(unused)) is not present in the path template",
            node,
        )
    end
    return
end

function _operation_id!(context::NormalizationContext, value, method, path, node)
    raw = get(value, "operationId", nothing)
    id = raw isa AbstractString && !isempty(raw) ? String(raw) :
         string(lowercase(String(method)), '_', replace(path, r"[^A-Za-z0-9]+" => "_"))
    if haskey(context.operation_ids, id)
        firstnode = context.operation_ids[id]
        _reference_error!(
            context.resolver,
            :duplicate_operation_id,
            "operationId $(repr(id)) is also used at $(string(firstnode.resource))#$(string(firstnode.pointer))",
            node,
        )
    else
        context.operation_ids[id] = node
    end
    return id
end

function _normalize_operation!(
    context::NormalizationContext,
    raw,
    node,
    method,
    path,
    direction,
    path_parameters,
    inherited_security,
    inherited_servers,
)
    object = _bind_object!(context.resolver, raw, node, :operation)
    object === nothing && return nothing
    own_parameters = _normalize_parameters!(
        context,
        get(object.value, "parameters", nothing),
        fieldnode(object, "parameters"),
    )
    parameters = _merge_parameters(path_parameters, own_parameters)
    query_count = count(parameter -> parameter.location === :query, parameters)
    querystring_count = count(
        parameter -> parameter.location === :querystring,
        parameters,
    )
    querystring_count <= 1 || _reference_error!(
        context.resolver,
        :querystring_parameter_count,
        "an operation can contain at most one querystring parameter",
        object.node,
    )
    (query_count == 0 || querystring_count == 0) || _reference_error!(
        context.resolver,
        :query_parameter_conflict,
        "query and querystring parameters cannot appear in the same operation",
        object.node,
    )
    direction === :request && _path_parameters!(context, path, parameters, object.node)
    request_body = haskey(object.value, "requestBody") ?
                   _normalize_request_body!(
        context,
        object.value["requestBody"],
        fieldnode(object, "requestBody"),
    ) : nothing
    responses = _normalize_responses!(
        context,
        get(object.value, "responses", nothing),
        fieldnode(object, "responses"),
    )
    security = haskey(object.value, "security") ?
               _normalize_security!(
        context,
        object.value["security"],
        fieldnode(object, "security"),
    ) : copy(inherited_security)
    servers = haskey(object.value, "servers") ?
              _normalize_servers!(
        context,
        object.value["servers"],
        fieldnode(object, "servers"),
    ) : copy(inherited_servers)
    tags = get(object.value, "tags", String[])
    operation = NormalizedOperation(
        _operation_id!(context, object.value, method, path, object.node),
        method,
        String(path),
        direction,
        _optional_string(object.value, "summary"),
        _optional_string(object.value, "description"),
        Tuple(String(tag) for tag in tags),
        get(object.value, "deprecated", false) === true,
        Tuple(parameters),
        request_body,
        Tuple(responses),
        Tuple(security),
        Tuple(servers),
        _raw_object(get(object.value, "callbacks", nothing)),
        _extensions(object.value),
        Provenance(object),
    )
    raw_callbacks = get(object.value, "callbacks", nothing)
    if raw_callbacks isa AbstractDict
        callbacks_node = fieldnode(object, "callbacks")
        for (name, raw_callback) in raw_callbacks
            callback_node = _childnode(callbacks_node, String(name))
            callback = _bind_object!(
                context.resolver,
                raw_callback,
                callback_node,
                :callback,
            )
            callback === nothing && continue
            append!(
                context.callback_operations,
                _normalize_paths!(
                    context,
                    callback.value,
                    callback.node,
                    :callback,
                    security,
                    servers,
                ),
            )
        end
    end
    return operation
end

const NORMALIZED_METHODS = (
    "get",
    "put",
    "post",
    "delete",
    "options",
    "head",
    "patch",
    "trace",
    "query",
)

function _normalize_path_item!(
    context::NormalizationContext,
    raw,
    node,
    path,
    direction,
    inherited_security,
    inherited_servers,
)
    object = _bind_object!(context.resolver, raw, node, :path_item)
    object === nothing && return NormalizedOperation[]
    parameters = _normalize_parameters!(
        context,
        get(object.value, "parameters", nothing),
        fieldnode(object, "parameters"),
    )
    servers = haskey(object.value, "servers") ?
              _normalize_servers!(
        context,
        object.value["servers"],
        fieldnode(object, "servers"),
    ) : inherited_servers
    output = NormalizedOperation[]
    for method_name in NORMALIZED_METHODS
        haskey(object.value, method_name) || continue
        if method_name == "query"
            version = _resource_version(context.resolver, object.node.resource)
            version.minor < 2 && continue
        end
        operation = _normalize_operation!(
            context,
            object.value[method_name],
            fieldnode(object, method_name),
            Symbol(uppercase(method_name)),
            path,
            direction,
            parameters,
            inherited_security,
            servers,
        )
        operation === nothing || push!(output, operation)
    end
    version = _resource_version(context.resolver, object.node.resource)
    additional = get(object.value, "additionalOperations", nothing)
    if version.minor >= 2 && additional isa AbstractDict
        additional_node = fieldnode(object, "additionalOperations")
        fixed = Set(uppercase.(NORMALIZED_METHODS))
        for (method_name, raw_operation) in additional
            normalized_method = uppercase(String(method_name))
            if normalized_method in fixed
                _reference_error!(
                    context.resolver,
                    :duplicate_http_method,
                    "additionalOperations duplicates fixed method $(repr(method_name))",
                    _childnode(additional_node, String(method_name)),
                )
                continue
            end
            operation = _normalize_operation!(
                context,
                raw_operation,
                _childnode(additional_node, String(method_name)),
                Symbol(String(method_name)),
                path,
                direction,
                parameters,
                inherited_security,
                servers,
            )
            operation === nothing || push!(output, operation)
        end
    end
    return output
end

function _normalize_paths!(
    context::NormalizationContext,
    value,
    node,
    direction,
    inherited_security,
    inherited_servers,
)
    output = NormalizedOperation[]
    value isa AbstractDict || return output
    templates = Dict{String,String}()
    for (path, raw) in value
        direction === :request && startswith(lowercase(String(path)), "x-") && continue
        startswith(String(path), "/") || direction !== :request || _reference_error!(
            context.resolver,
            :path_prefix,
            "path template $(repr(path)) must start with `/`",
            _childnode(node, String(path)),
        )
        if direction === :request
            signature = replace(String(path), r"\{[^{}]+\}" => "{}")
            previous = get(templates, signature, nothing)
            if previous !== nothing && previous != String(path)
                message = "path template $(repr(path)) is equivalent to $(repr(previous))"
                if context.resolver.strict
                    _reference_error!(
                        context.resolver,
                        :ambiguous_path_template,
                        message,
                        _childnode(node, String(path)),
                    )
                else
                    _warning!(
                        context.resolver.bag,
                        :ambiguous_path_template,
                        message * "; both operations are retained in permissive mode",
                        SourceLocation(
                            node.resource,
                            _childnode(node, String(path)).pointer,
                        ),
                    )
                end
            else
                templates[signature] = String(path)
            end
        end
        append!(
            output,
            _normalize_path_item!(
                context,
                raw,
                _childnode(node, String(path)),
                String(path),
                direction,
                inherited_security,
                inherited_servers,
            ),
        )
    end
    return output
end

function _normalize_component_schemas!(context::NormalizationContext, value, node)
    output = Pair{String,SchemaHandle}[]
    value isa AbstractDict || return output
    for (name, raw) in value
        handle = _schema_handle!(context, raw, _childnode(node, String(name)))
        handle === nothing || push!(output, String(name) => handle)
    end
    return output
end

function _oauth_scopes(scheme::NormalizedSecurityScheme)
    output = Set{String}()
    scheme.flows isa AbstractDict || return output
    for flow in values(scheme.flows)
        flow isa AbstractDict || continue
        scopes = get(flow, "scopes", nothing)
        scopes isa AbstractDict || continue
        union!(output, String.(keys(scopes)))
    end
    return output
end

function _validate_security_references!(context, requirements, schemes)
    known = Dict(scheme.name => scheme for scheme in schemes)
    for requirement in requirements
        for (name, scopes) in requirement.alternatives
            scheme = get(known, name, nothing)
            version = _resource_version(
                context.resolver,
                requirement.provenance.node.resource,
            )
            if scheme === nothing && version.minor >= 2
                resolved = try
                    _resolve_reference!(
                        context.resolver,
                        requirement.provenance.node,
                        name,
                    )
                catch
                    nothing
                end
                if resolved !== nothing
                    scheme = _normalize_security_scheme!(
                        context,
                        name,
                        resolved.value,
                        resolved.id,
                    )
                    if scheme !== nothing
                        known[name] = scheme
                        push!(schemes, scheme)
                    end
                end
            end
            scheme === nothing && begin
                # Strict mode enforces the Security Requirement Object's MUST
                # (the name corresponds to a declared scheme). Permissive mode
                # supports the specification's multi-document pattern, where a
                # referenced document names schemes its entry document
                # declares: the scheme is treated as externally declared, and
                # generation excludes it from credential enforcement.
                if context.resolver.strict
                    _reference_error!(
                        context.resolver,
                        :unknown_security_scheme,
                        "security requirement refers to unknown scheme $(repr(name))",
                        requirement.provenance.node,
                    )
                else
                    _warning!(
                        context.resolver.bag,
                        :unknown_security_scheme,
                        "security requirement refers to unknown scheme $(repr(name)); " *
                        "treating it as externally declared and excluding it from " *
                        "generated credential enforcement",
                        SourceLocation(
                            requirement.provenance.node.resource,
                            requirement.provenance.node.pointer,
                        ),
                    )
                end
                continue
            end
            if version.minor < 2 &&
               !(scheme.type in (:oauth2, :openidconnect, :open_id_connect)) &&
               !isempty(scopes)
                _reference_error!(
                    context.resolver,
                    :invalid_security_scopes,
                    "security scheme $(repr(name)) does not accept OAuth scopes",
                    requirement.provenance.node,
                )
            elseif scheme.type === :oauth2
                missing = setdiff(Set(scopes), _oauth_scopes(scheme))
                isempty(missing) || _reference_error!(
                    context.resolver,
                    :unknown_oauth_scope,
                    "security requirement uses undefined OAuth scopes $(join(repr.(sort!(collect(missing))), ", "))",
                    requirement.provenance.node,
                )
            end
        end
    end
    return
end

"""
    OpenAPI.normalize(source; options...) -> NormalizedAPI

Load, resolve, and normalize an OpenAPI 3.0, 3.1, or 3.2 description into a
stable intermediate representation. Strict mode rejects undefined Path Item
reference sibling behavior and all semantic errors before code generation.
"""
function normalize(
    source;
    strict::Bool = true,
    max_diagnostics::Integer = 1_000,
    base_uri = nothing,
    format::Symbol = :auto,
    retriever::Union{Nothing,Resources.AbstractRetriever} = nothing,
    file_roots::AbstractVector{<:AbstractString} = String[],
    allow_remote_refs::Bool = false,
    max_resources::Integer = 256,
    max_bytes::Integer = 16 * 1024 * 1024,
    max_nodes::Integer = 1_000_000,
    max_depth::Integer = 512,
)
    document = load(
        source;
        max_diagnostics,
        base_uri,
        format,
        max_bytes,
        max_nodes,
        max_depth,
    )
    bag = DiagnosticBag(max_diagnostics)
    resolver = ResolverContext(
        document,
        bag;
        retriever,
        strict,
        file_roots,
        allow_remote_refs,
        max_resources,
        max_bytes,
        max_nodes,
        max_depth,
    )
    context = NormalizationContext(
        resolver,
        SchemaWorkspace(nothing),
        Dict{Resources.NodeId,SchemaHandle}(),
        Dict{String,Resources.NodeId}(),
        NormalizedOperation[],
    )
    rootnode = Resources.NodeId(document.resource.id, Resources.JSONPointer())
    root = BoundObject(document.resource.contents, rootnode)
    info = root.value["info"]
    servers = _normalize_servers!(
        context,
        get(root.value, "servers", nothing),
        _childnode(rootnode, "servers"),
    )
    security = _normalize_security!(
        context,
        get(root.value, "security", nothing),
        _childnode(rootnode, "security"),
    )
    components = get(root.value, "components", nothing)
    component_node = _childnode(rootnode, "components")
    schemes = _normalize_security_schemes!(
        context,
        components isa AbstractDict ? get(components, "securitySchemes", nothing) : nothing,
        _childnode(component_node, "securitySchemes"),
    )
    schemas = _normalize_component_schemas!(
        context,
        components isa AbstractDict ? get(components, "schemas", nothing) : nothing,
        _childnode(component_node, "schemas"),
    )
    operations = _normalize_paths!(
        context,
        get(root.value, "paths", nothing),
        _childnode(rootnode, "paths"),
        :request,
        security,
        servers,
    )
    if haskey(root.value, "webhooks")
        append!(
            operations,
            _normalize_paths!(
                context,
                root.value["webhooks"],
                _childnode(rootnode, "webhooks"),
                :webhook,
                security,
                servers,
            ),
        )
    end
    append!(operations, context.callback_operations)
    _validate_security_references!(context, security, schemes)
    for operation in operations
        _validate_security_references!(context, operation.security, schemes)
    end
    _compile_schemas!(context)
    _throw_on_errors("Cannot normalize OpenAPI document", bag.diagnostics)
    return NormalizedAPI(
        document,
        Resources.freeze(resolver.registry),
        String(info["title"]),
        String(info["version"]),
        _optional_string(info, "description"),
        Tuple(servers),
        Tuple(schemes),
        Tuple(security),
        Tuple(schemas),
        Tuple(operations),
        _extensions(root.value),
        Tuple(copy(bag.diagnostics)),
    )
end
