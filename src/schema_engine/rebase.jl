# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

function _mutable_json(value::AbstractDict)
    output = JSON.Object{String,Any}()
    sizehint!(output, length(value))
    for (key, child) in value
        output[String(key)] = _mutable_json(child)
    end
    return output
end

_mutable_json(value::AbstractVector) = Any[_mutable_json(child) for child in value]
_mutable_json(value) = value

function _reference_fragment(reference::AbstractString)
    uri = URIs.URI(reference)
    if isempty(uri.fragment)
        return endswith(reference, '#') ? "#" : ""
    end
    return "#" * uri.fragment
end

function _rebased_reference(
    keyword::String,
    raw::AbstractString,
    target::Resources.NodeId,
    resource_ids::Dict{Resources.ResourceId,Resources.ResourceId},
)
    resource = string(resource_ids[target.resource])
    if keyword == "\$ref"
        pointer = string(target.pointer)
        return isempty(pointer) ? resource : resource * "#" * pointer
    end
    # Dynamic and recursive references must keep their anchor fragment. A JSON
    # Pointer can use the compiler's canonical target pointer.
    parsed = Resources.Reference(target.resource, raw)
    fragment = parsed.fragment
    if fragment isa Resources.AnchorFragment
        return resource * "#" * fragment.name
    elseif fragment isa Resources.PointerFragment
        pointer = string(target.pointer)
        return isempty(pointer) ? resource * "#" : resource * "#" * pointer
    end
    return resource * _reference_fragment(raw)
end

function _rebased_identifier(
    raw::AbstractString,
    node::CompiledNode,
    resource_ids::Dict{Resources.ResourceId,Resources.ResourceId},
)
    return string(resource_ids[node.id.resource]) * _reference_fragment(raw)
end

function _top_level_resources(registry::Resources.AbstractRegistry)
    resources = Resources.Resource[
        resource for resource in values(getfield(registry, :resources))
        if isempty(resource.source.pointer) &&
           Resources.resource(registry, resource.retrieval).id == resource.id
    ]
    sort!(resources; by = resource -> string(resource.id))
    return resources
end

function _normalize_resource_ids(registry, mapping)
    output = Dict{Resources.ResourceId,Resources.ResourceId}()
    for id in keys(getfield(registry, :resources))
        target = get(mapping, id, nothing)
        target === nothing && throw(
            ArgumentError("no replacement identifier was supplied for resource $(repr(string(id)))"),
        )
        output[id] = target isa Resources.ResourceId ? target : Resources.ResourceId(target)
    end
    length(Set(values(output))) == length(output) || throw(
        ArgumentError("replacement resource identifiers must be unique"),
    )
    return output
end

function _rewrite_resource_documents(template::CompiledSchema, resource_ids)
    registry = template.registry
    documents = Dict{Resources.ResourceId,Any}(
        resource.id => _mutable_json(resource.contents) for
        resource in _top_level_resources(registry)
    )

    seen = Set{Int}()
    for node in values(getfield(template, :evaluation_nodes))
        node.index in seen && continue
        push!(seen, node.index)
        source = _source_node(registry, node.id)
        owner = Resources.resource(registry, source.resource)
        document = get(documents, owner.id, nothing)
        document === nothing && continue
        schema = Resources.resolve(document, source.pointer)
        schema isa AbstractDict || continue
        keyword = node.dialect.id_keyword
        identifier = get(schema, keyword, nothing)
        identifier isa AbstractString || continue
        schema[keyword] = _rebased_identifier(identifier, node, resource_ids)
    end

    for ((node, keyword), target) in getfield(template, :references)
        source = _source_node(registry, node)
        owner = Resources.resource(registry, source.resource)
        document = get(documents, owner.id, nothing)
        document === nothing && continue
        schema = Resources.resolve(document, source.pointer)
        schema isa AbstractDict || continue
        raw = get(schema, keyword, nothing)
        raw isa AbstractString || continue
        schema[keyword] = _rebased_reference(keyword, raw, target, resource_ids)
    end
    return documents
end

function _mapped_raw_node(resource_ids, node::Resources.NodeId)
    return Resources.NodeId(resource_ids[node.resource], node.pointer)
end

function _mapped_node(registry, resource_ids, node::Resources.NodeId)
    canonical = Resources.canonical(registry, node)
    return _mapped_raw_node(resource_ids, canonical)
end

function _rebased_registry(registry, resource_ids, documents)
    output = Resources.Registry()
    resources = collect(values(getfield(registry, :resources)))
    sort!(resources; by = resource -> (length(resource.source.pointer), string(resource.id)))
    for original in resources
        owner = Resources.resource(registry, original.source.resource)
        id = resource_ids[original.id]
        owner_id = resource_ids[owner.id]
        contents = original.id == owner.id ? documents[owner.id] :
                   Resources.resolve(documents[owner.id], original.source.pointer)
        Resources.register!(
            output,
            Resources.Resource(
                id,
                contents;
                retrieval = owner_id,
                source = Resources.NodeId(owner_id, original.source.pointer),
                media_type = original.media_type,
            );
            alias_retrieval = false,
        )
    end

    dynamic = getfield(registry, :dynamic_anchors)
    anchors = collect(getfield(registry, :anchors))
    sort!(anchors; by = entry -> (string(entry.first[1]), entry.first[2]))
    for ((resource, name), node) in anchors
        Resources.register_anchor!(
            output,
            resource_ids[resource],
            name,
            node.pointer;
            dynamic = haskey(dynamic, (resource, name)),
        )
    end
    boundaries = collect(getfield(registry, :boundaries))
    sort!(
        boundaries;
        by = entry -> (string(entry.first.resource), string(entry.first.pointer)),
    )
    for (source, target) in boundaries
        Resources.register_boundary!(
            output,
            _mapped_raw_node(resource_ids, source),
            _mapped_raw_node(resource_ids, target),
        )
    end
    return Resources.freeze(output)
end

function _rebased_template(template, resource_ids, registry)
    original_registry = template.registry
    original_nodes = getfield(template, :evaluation_nodes)
    nodes_by_index = Dict{Int,CompiledNode}()
    for node in values(original_nodes)
        haskey(nodes_by_index, node.index) && continue
        id = _mapped_node(original_registry, resource_ids, node.id)
        resource = Resources.resource(registry, id.resource)
        value = Resources.resolve(resource.contents, id.pointer)
        nodes_by_index[node.index] = CompiledNode(node.index, id, value, node.dialect)
    end

    evaluation_nodes = Dict{Resources.NodeId,CompiledNode}()
    for (id, node) in original_nodes
        mapped = _mapped_node(original_registry, resource_ids, id)
        evaluation_nodes[mapped] = nodes_by_index[node.index]
    end
    for node in values(nodes_by_index)
        evaluation_nodes[node.id] = node
    end

    dialects = Dict(
        _mapped_node(original_registry, resource_ids, id) => dialect for
        (id, dialect) in getfield(template, :dialects)
    )
    transitions = Dict{Tuple{Int,Tuple{Vararg{String}}},CompiledNode}()
    for (key, node) in getfield(template, :transitions)
        transitions[key] = nodes_by_index[node.index]
    end
    references = Dict(
        (
            _mapped_node(original_registry, resource_ids, source),
            keyword,
        ) => _mapped_node(original_registry, resource_ids, target) for
        ((source, keyword), target) in getfield(template, :references)
    )
    recursive_anchors = Set(
        resource_ids[resource] for
        resource in getfield(template, :recursive_anchors)
    )
    root = _mapped_node(original_registry, resource_ids, template.root)
    resource = Resources.resource(registry, root.resource)
    data = Resources.resolve(resource.contents, root.pointer)
    return CompiledSchema(
        data,
        template.dialect,
        registry,
        root,
        dialects,
        copy(getfield(template, :dialect_aliases)),
        evaluation_nodes,
        transitions,
        template.uses_annotations,
        recursive_anchors,
        references,
        copy(getfield(template, :regexes)),
        Resources.DisabledRetriever(),
    )
end

"""
    rebase(schemas::CompiledSchemas, resource_ids) -> CompiledSchemas

Create an equivalent, self-contained compiled graph under replacement resource
identifiers. `resource_ids` must map every canonical resource in `schemas` to a
unique replacement identifier. Schema identifiers and reference keywords are
rewritten from the compiled graph, so relative references, embedded resources,
anchors, dynamic references, and recursive references retain their meaning.

Requested root identifiers from `schemas` remain valid lookup keys. The graph's
canonical roots and all serialized resource data use only replacement ids.
"""
function rebase(schemas::CompiledSchemas, mapping::AbstractDict)
    template = getfield(schemas, :template)
    registry = template.registry
    resource_ids = _normalize_resource_ids(registry, mapping)
    documents = _rewrite_resource_documents(template, resource_ids)

    rebased_registry = _rebased_registry(registry, resource_ids, documents)
    rebased_template = _rebased_template(template, resource_ids, rebased_registry)
    preserved = Dict{Resources.NodeId,Resources.NodeId}()
    for (requested, raw_root) in getfield(schemas, :roots)
        root = _mapped_node(registry, resource_ids, raw_root)
        preserved[requested] = root
        if haskey(resource_ids, requested.resource)
            mapped_requested = _mapped_raw_node(resource_ids, requested)
            preserved[mapped_requested] = root
        end
        preserved[root] = root
    end
    return CompiledSchemas(rebased_template, preserved)
end
