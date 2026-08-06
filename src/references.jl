"""A bounded retriever for relative files and explicitly allowed HTTP resources."""
struct DocumentRetriever <: Resources.AbstractRetriever
    file::Union{Nothing,Resources.FileRetriever}
    allow_http::Bool
    allowed_origins::Tuple{Vararg{String}}
    max_bytes::Int
end

function _origin(id::Resources.ResourceId)
    uri = id.uri
    scheme = lowercase(uri.scheme)
    scheme in ("http", "https") || return nothing
    port = isempty(uri.port) ? (scheme == "https" ? "443" : "80") : uri.port
    return string(scheme, "://", lowercase(uri.host), ':', port)
end

function DocumentRetriever(
    document::SourceDocument;
    file_roots::AbstractVector{<:AbstractString} = String[],
    allow_remote_refs::Bool = false,
    max_bytes::Integer = 16 * 1024 * 1024,
)
    max_bytes > 0 || throw(ArgumentError("max_bytes must be positive"))
    roots = String[String(root) for root in file_roots]
    retrieval = document.resource.retrieval
    if lowercase(retrieval.uri.scheme) == "file"
        path = Resources.URIs.unescapeuri(retrieval.uri.path)
        pushfirst!(roots, dirname(path))
    end
    unique!(roots)
    file = isempty(roots) ? nothing : Resources.FileRetriever(roots; max_bytes)
    initial_origin = _origin(retrieval)
    origins = initial_origin === nothing ? () : (initial_origin,)
    return DocumentRetriever(file, allow_remote_refs, origins, Int(max_bytes))
end

function Resources.retrieve(retriever::DocumentRetriever, id::Resources.ResourceId)
    scheme = lowercase(id.uri.scheme)
    if scheme in ("", "file")
        retriever.file === nothing && throw(
            Resources.RetrievalError(id, "external file retrieval is disabled"),
        )
        return Resources.retrieve(retriever.file, id)
    elseif scheme in ("http", "https")
        origin = _origin(id)
        allowed = retriever.allow_http || origin in retriever.allowed_origins
        allowed || throw(
            Resources.RetrievalError(
                id,
                "cross-origin HTTP retrieval is disabled; pass allow_remote_refs=true to enable it",
            ),
        )
        Base.get_extension(@__MODULE__, :OpenAPIHTTPExt) === nothing && throw(
            Resources.RetrievalError(id, "HTTP retrieval requires HTTP.jl to be loaded"),
        )
        return fetchresource(id, retriever.max_bytes)
    end
    throw(Resources.RetrievalError(id, "URI scheme $(repr(scheme)) is not allowed"))
end

struct BoundObject
    value::AbstractDict
    node::Resources.NodeId
    field_nodes::Dict{String,Resources.NodeId}
    reference_chain::Tuple{Vararg{Resources.NodeId}}
end

function BoundObject(value::AbstractDict, node::Resources.NodeId)
    return BoundObject(
        value,
        node,
        Dict{String,Resources.NodeId}(),
        (node,),
    )
end

function fieldnode(object::BoundObject, name::AbstractString)
    return get(object.field_nodes, String(name), _childnode(object.node, name))
end

function _childnode(node::Resources.NodeId, token::AbstractString)
    return Resources.NodeId(node.resource, node.pointer / token)
end

mutable struct ResolverContext{R<:Resources.AbstractRetriever}
    root::SourceDocument
    registry::Resources.Registry
    versions::Dict{Resources.ResourceId,DocumentVersion}
    formats::Dict{Resources.ResourceId,Symbol}
    retriever::R
    bag::DiagnosticBag
    strict::Bool
    max_resources::Int
    max_nodes::Int
    max_depth::Int
    loaded::Int
    resolving::Set{Resources.NodeId}
end

function ResolverContext(
    document::SourceDocument,
    bag::DiagnosticBag;
    retriever::Union{Nothing,Resources.AbstractRetriever} = nothing,
    strict::Bool = true,
    file_roots::AbstractVector{<:AbstractString} = String[],
    allow_remote_refs::Bool = false,
    max_resources::Integer = 256,
    max_bytes::Integer = 16 * 1024 * 1024,
    max_nodes::Integer = 1_000_000,
    max_depth::Integer = 512,
)
    max_resources > 0 || throw(ArgumentError("max_resources must be positive"))
    selected = something(
        retriever,
        DocumentRetriever(
            document;
            file_roots,
            allow_remote_refs,
            max_bytes,
        ),
    )
    registry = Resources.Registry()
    Resources.register!(registry, document.resource)
    return ResolverContext(
        document,
        registry,
        Dict(document.resource.id => document.version),
        Dict(document.resource.id => document.format),
        selected,
        bag,
        strict,
        Int(max_resources),
        Int(max_nodes),
        Int(max_depth),
        1,
        Set{Resources.NodeId}(),
    )
end

function _resource_version(context::ResolverContext, id::Resources.ResourceId)
    registered = Resources.resource(context.registry, id)
    return get(context.versions, registered.id, context.root.version)
end

function _resource_format(id::Resources.ResourceId, media_type)
    media_type !== nothing && return _format_from_hint(media_type)
    return _format_from_hint(id.uri.path)
end

function _register_retrieved!(
    context::ResolverContext,
    requested::Resources.ResourceId,
    retrieved::Resources.RetrievedResource,
)
    context.loaded < context.max_resources || throw(
        Resources.RetrievalError(requested, "OpenAPI resource limit reached"),
    )
    format = _resource_format(retrieved.id, retrieved.media_type)
    format = format === :auto ? _sniff_format(getfield(retrieved, :bytes), :auto) : format
    root, locations = _parse_source(
        getfield(retrieved, :bytes),
        format;
        max_nodes = context.max_nodes,
        max_depth = context.max_depth,
        source_locations = true,
    )
    retrieval = retrieved.id
    version = nothing
    canonical = retrieval
    if root isa AbstractDict && get(root, "openapi", nothing) isa AbstractString
        version = try
            DocumentVersion(root["openapi"])
        catch error
            throw(Resources.RetrievalError(requested, sprint(showerror, error)))
        end
        canonical = _canonical_document_id(root, retrieval, version, context.bag)
    end
    resource = Resources.Resource(
        canonical,
        root;
        retrieval,
        media_type = retrieved.media_type,
    )
    aliases = requested == retrieval ? Resources.ResourceId[] : [requested]
    if haskey(context.registry, canonical)
        for alias in (retrieval, requested)
            haskey(context.registry, alias) ||
                Resources.register_alias!(context.registry, alias, canonical)
        end
    else
        Resources.register!(context.registry, resource; aliases)
        context.loaded += 1
    end
    if version !== nothing
        context.versions[canonical] = version
        context.formats[canonical] = format
        external = SourceDocument(
            resource,
            version,
            format,
            locations,
        )
        _structural_diagnostics!(context.bag, external)
    end
    return Resources.resource(context.registry, requested)
end

function _ensure_resource!(context::ResolverContext, id::Resources.ResourceId)
    haskey(context.registry, id) && return Resources.resource(context.registry, id)
    retrieved = try
        Resources.retrieve(context.retriever, id)
    catch error
        throw(Resources.RetrievalError(id, sprint(showerror, error)))
    end
    return _register_retrieved!(context, id, retrieved)
end

function _resolve_reference!(
    context::ResolverContext,
    base::Resources.NodeId,
    raw::AbstractString,
)
    reference = try
        Resources.Reference(base.resource, raw)
    catch error
        throw(ArgumentError("invalid reference $(repr(raw)): $(sprint(showerror, error))"))
    end
    _ensure_resource!(context, reference.resource)
    return Resources.resolve(context.registry, reference)
end

function _reference_error!(context, code, message, node)
    _error!(context.bag, code, message, SourceLocation(node.resource, node.pointer))
    return nothing
end

function _bind_object!(
    context::ResolverContext,
    value,
    node::Resources.NodeId,
    kind::Symbol,
)
    value isa AbstractDict || begin
        _reference_error!(
            context,
            :object_type,
            "expected an object for $(replace(String(kind), '_' => ' '))",
            node,
        )
        return nothing
    end
    raw_reference = get(value, "\$ref", nothing)
    raw_reference === nothing && return BoundObject(value, node)
    raw_reference isa AbstractString || begin
        _reference_error!(context, :invalid_reference, "`\$ref` must be a string", node)
        return nothing
    end
    resolved = try
        _resolve_reference!(context, node, raw_reference)
    catch error
        _reference_error!(context, :unresolved_reference, sprint(showerror, error), node)
        return nothing
    end
    target = resolved.id
    target in context.resolving && begin
        _reference_error!(
            context,
            :reference_cycle,
            "a non-schema reference cycle reaches $(string(target.resource))#$(string(target.pointer))",
            node,
        )
        return nothing
    end
    resolved.value isa AbstractDict || begin
        _reference_error!(
            context,
            :reference_target_type,
            "reference target is not an object",
            node,
        )
        return nothing
    end
    push!(context.resolving, target)
    bound = try
        _bind_object!(context, resolved.value, target, kind)
    finally
        delete!(context.resolving, target)
    end
    bound === nothing && return nothing

    siblings = String[String(key) for key in keys(value) if key != "\$ref"]
    isempty(siblings) && return BoundObject(
        bound.value,
        bound.node,
        bound.field_nodes,
        (node, bound.reference_chain...),
    )
    referring_version = _resource_version(context, node.resource)
    if kind === :path_item
        message = "Path Item Object `\$ref` siblings have undefined behavior"
        if context.strict
            _reference_error!(context, :path_item_reference_siblings, message, node)
            return nothing
        end
        _warning!(
            context.bag,
            :path_item_reference_siblings,
            message * "; local fields override the target in permissive mode",
            SourceLocation(node.resource, node.pointer),
        )
        merged = JSON.Object{String,Any}()
        for (key, item) in bound.value
            merged[String(key)] = item
        end
        field_nodes = copy(bound.field_nodes)
        for key in siblings
            merged[key] = value[key]
            field_nodes[key] = _childnode(node, key)
        end
        return BoundObject(
            merged,
            bound.node,
            field_nodes,
            (node, bound.reference_chain...),
        )
    end

    allowed = referring_version.minor == 0 ? Set{String}() : Set(("summary", "description"))
    ignored = [key for key in siblings if !(key in allowed)]
    isempty(ignored) || _warning!(
        context.bag,
        :ignored_reference_siblings,
        "Reference Object siblings $(join(repr.(ignored), ", ")) are ignored by OAS $(referring_version.major).$(referring_version.minor)",
        SourceLocation(node.resource, node.pointer),
    )
    overrides = [key for key in siblings if key in allowed]
    isempty(overrides) && return BoundObject(
        bound.value,
        bound.node,
        bound.field_nodes,
        (node, bound.reference_chain...),
    )
    merged = JSON.Object{String,Any}()
    for (key, item) in bound.value
        merged[String(key)] = item
    end
    field_nodes = copy(bound.field_nodes)
    for key in overrides
        merged[key] = value[key]
        field_nodes[key] = _childnode(node, key)
    end
    return BoundObject(
        merged,
        bound.node,
        field_nodes,
        (node, bound.reference_chain...),
    )
end

function _schema_retriever(context::ResolverContext)
    return SchemaResourceRetriever(
        context.retriever,
        context.root.version.minor == 0,
        context.root.version.minor == 0 && !context.strict,
        context.max_nodes,
        context.max_depth,
    )
end

"""Adapter that converts YAML resources to JSON before the schema engine compiles them."""
struct SchemaResourceRetriever{R<:Resources.AbstractRetriever} <:
       Resources.AbstractRetriever
    retriever::R
    oas30::Bool
    permissive_nullable::Bool
    max_nodes::Int
    max_depth::Int
end

function Resources.retrieve(retriever::SchemaResourceRetriever, id::Resources.ResourceId)
    resource = Resources.retrieve(retriever.retriever, id)
    format = _resource_format(resource.id, resource.media_type)
    bytes = getfield(resource, :bytes)
    detected = format === :auto ? _sniff_format(bytes, :auto) : format
    if retriever.oas30 || detected === :yaml
        parsed = _parse_source(
            bytes,
            detected;
            max_nodes = retriever.max_nodes,
            max_depth = retriever.max_depth,
        )
        retriever.oas30 && (parsed = _oas30_schema_compat(
            parsed;
            permissive_nullable = retriever.permissive_nullable,
        ))
        bytes = Vector{UInt8}(codeunits(JSON.json(parsed)))
    end
    return Resources.RetrievedResource(
        resource.id,
        bytes;
        media_type = "application/schema+json",
    )
end
