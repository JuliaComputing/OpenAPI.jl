# Copyright (c) 2026: fredo-dedup, quinnj, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

"""Generic, non-mutating JSON resource identification and lookup."""
module Resources

import ..URIs

struct PointerError <: Exception
    pointer::String
    token::Int
    reason::String
end

function Base.showerror(io::IO, err::PointerError)
    location = err.token == 0 ? "root" : "token $(err.token)"
    return print(
        io,
        "invalid JSON Pointer ",
        repr(err.pointer),
        " at ",
        location,
        ": ",
        err.reason,
    )
end

"""A parsed RFC 6901 JSON Pointer."""
struct JSONPointer
    tokens::Tuple{Vararg{String}}
end

JSONPointer() = JSONPointer(())

function _unescape_token(
    token::AbstractString,
    pointer::AbstractString,
    index::Int,
)
    i = firstindex(token)
    last = lastindex(token)
    io = IOBuffer()
    while i <= last
        char = token[i]
        if char != '~'
            write(io, char)
            i = nextind(token, i)
            continue
        end
        next = nextind(token, i)
        if next > last || !(token[next] in ('0', '1'))
            throw(PointerError(String(pointer), index, "invalid '~' escape"))
        end
        write(io, token[next] == '0' ? '~' : '/')
        i = nextind(token, next)
    end
    return String(take!(io))
end

function JSONPointer(pointer::AbstractString)
    isempty(pointer) && return JSONPointer()
    startswith(pointer, '/') || throw(
        PointerError(
            String(pointer),
            0,
            "a non-empty pointer must start with '/'",
        ),
    )
    raw = split(
        SubString(pointer, nextind(pointer, firstindex(pointer))),
        '/';
        keepempty = true,
    )
    tokens = ntuple(length(raw)) do i
        return _unescape_token(raw[i], pointer, i)
    end
    return JSONPointer(tokens)
end

function _escape_token(token::String)
    return replace(replace(token, "~" => "~0"), "/" => "~1")
end

function Base.string(pointer::JSONPointer)
    isempty(pointer.tokens) && return ""
    return "/" * join((_escape_token(token) for token in pointer.tokens), "/")
end

function Base.show(io::IO, pointer::JSONPointer)
    return print(io, "JSONPointer(", repr(string(pointer)), ")")
end
Base.length(pointer::JSONPointer) = length(pointer.tokens)
Base.isempty(pointer::JSONPointer) = isempty(pointer.tokens)
Base.iterate(pointer::JSONPointer, state...) = iterate(pointer.tokens, state...)
Base.getindex(pointer::JSONPointer, index::Integer) = pointer.tokens[index]

function Base.:/(pointer::JSONPointer, token::AbstractString)
    return JSONPointer((pointer.tokens..., String(token)))
end

struct FrozenObject <: AbstractDict{String,Any}
    entries::Tuple{Vararg{Pair{String,Any}}}
    index::Dict{String,Int}
end

Base.IteratorSize(::Type{<:FrozenObject}) = Base.HasLength()
Base.length(object::FrozenObject) = length(object.entries)
Base.iterate(object::FrozenObject, state...) = iterate(object.entries, state...)
Base.copy(object::FrozenObject) = object

function Base.getproperty(object::FrozenObject, name::Symbol)
    name === :index && return copy(getfield(object, :index))
    return getfield(object, name)
end

function Base.haskey(object::FrozenObject, key)
    return haskey(getfield(object, :index), key)
end

function Base.getindex(object::FrozenObject, key)
    position = getfield(object, :index)[key]
    return getfield(object, :entries)[position].second
end

function Base.get(object::FrozenObject, key, default)
    position = get(getfield(object, :index), key, 0)
    return position == 0 ? default : getfield(object, :entries)[position].second
end

function Base.get(default::Union{Function,Type}, object::FrozenObject, key)
    position = get(getfield(object, :index), key, 0)
    return position == 0 ? default() :
           getfield(object, :entries)[position].second
end

struct FrozenArray <: AbstractVector{Any}
    entries::Tuple{Vararg{Any}}
end

Base.IndexStyle(::Type{FrozenArray}) = IndexLinear()
Base.size(array::FrozenArray) = (length(array.entries),)
Base.getindex(array::FrozenArray, index::Int) = array.entries[index]
Base.copy(array::FrozenArray) = array

"""Create a read-only recursive view of a parsed JSON value."""
freeze(value::FrozenObject) = value
freeze(value::FrozenArray) = value

function freeze(value::AbstractDict)
    entries = Pair{String,Any}[]
    index = Dict{String,Int}()
    sizehint!(entries, length(value))
    sizehint!(index, length(value))
    for (key, item) in value
        key isa AbstractString ||
            throw(ArgumentError("JSON object keys must be strings"))
        normalized = String(key)
        push!(entries, normalized => freeze(item))
        index[normalized] = length(entries)
    end
    return FrozenObject(Tuple(entries), index)
end

function freeze(value::AbstractVector)
    entries = Any[]
    sizehint!(entries, length(value))
    for item in value
        push!(entries, freeze(item))
    end
    return FrozenArray(Tuple(entries))
end

freeze(value) = value

function _array_index(pointer::JSONPointer, token::String, index::Int)
    isempty(token) && throw(
        PointerError(string(pointer), index, "an array index cannot be empty"),
    )
    occursin(r"^(0|[1-9][0-9]*)$", token) || throw(
        PointerError(
            string(pointer),
            index,
            "expected an unsigned decimal array index",
        ),
    )
    value = tryparse(Int, token)
    value === nothing && throw(
        PointerError(
            string(pointer),
            index,
            "expected a non-negative integer array index",
        ),
    )
    value < 0 && throw(
        PointerError(
            string(pointer),
            index,
            "expected a non-negative integer array index",
        ),
    )
    return value + 1
end

function resolve(document, pointer::JSONPointer)
    value = document
    for (index, token) in enumerate(pointer.tokens)
        if value isa AbstractDict
            haskey(value, token) || throw(
                PointerError(
                    string(pointer),
                    index,
                    "object member $(repr(token)) does not exist",
                ),
            )
            value = value[token]
        elseif value isa AbstractVector
            julia_index = _array_index(pointer, token, index)
            checkbounds(Bool, value, julia_index) || throw(
                PointerError(
                    string(pointer),
                    index,
                    "array index $(repr(token)) is out of bounds",
                ),
            )
            value = value[julia_index]
        else
            throw(
                PointerError(
                    string(pointer),
                    index,
                    "cannot traverse a $(typeof(value)) value",
                ),
            )
        end
    end
    return value
end

"""A canonical, fragment-free resource identifier."""
struct ResourceId
    uri::URIs.URI
    text::String

    function ResourceId(uri::URIs.URI)
        isempty(uri.fragment) || throw(
            ArgumentError("a resource identifier cannot contain a fragment"),
        )
        scheme = lowercase(uri.scheme)
        host = lowercase(uri.host)
        path = _remove_dot_segments(_normalize_percent_encoding(uri.path))
        if scheme in ("http", "https") && !isempty(host) && isempty(path)
            path = "/"
        end
        normalized = _build_uri(
            scheme,
            _normalize_percent_encoding(uri.userinfo),
            host,
            _normalized_port(scheme, uri.port),
            path,
            _normalize_percent_encoding(uri.query),
            _has_authority(uri),
        )
        return new(normalized, string(normalized))
    end
end

function _is_unreserved(byte::UInt8)
    return UInt8('A') <= byte <= UInt8('Z') ||
           UInt8('a') <= byte <= UInt8('z') ||
           UInt8('0') <= byte <= UInt8('9') ||
           byte == UInt8('-') ||
           byte == UInt8('.') ||
           byte == UInt8('_') ||
           byte == UInt8('~')
end

function _normalize_percent_encoding(value::AbstractString)
    isempty(value) && return value
    bytes = codeunits(value)
    output = IOBuffer()
    index = 1
    while index <= length(bytes)
        if bytes[index] == UInt8('%') && index + 2 <= length(bytes)
            encoded = tryparse(
                UInt8,
                String(copy(bytes[(index+1):(index+2)]));
                base = 16,
            )
            if encoded !== nothing
                if _is_unreserved(encoded)
                    write(output, encoded)
                else
                    print(
                        output,
                        '%',
                        uppercase(string(encoded; base = 16, pad = 2)),
                    )
                end
                index += 3
                continue
            end
        end
        write(output, bytes[index])
        index += 1
    end
    return String(take!(output))
end

function _remove_last_segment(path::String)
    separator = findlast(==('/'), path)
    separator === nothing && return ""
    separator == firstindex(path) && return ""
    return String(SubString(path, firstindex(path), prevind(path, separator)))
end

function _move_first_segment(path::String)
    start = firstindex(path)
    search = path[start] == '/' ? nextind(path, start) : start
    separator = findnext(==('/'), path, search)
    separator === nothing && return (path, "")
    segment = String(SubString(path, start, prevind(path, separator)))
    return (segment, String(SubString(path, separator)))
end

function _remove_dot_segments(path::AbstractString)
    input = String(path)
    output = ""
    while !isempty(input)
        if startswith(input, "../")
            input = input[4:end]
        elseif startswith(input, "./")
            input = input[3:end]
        elseif startswith(input, "/./")
            input = input[3:end]
        elseif input == "/."
            input = "/"
        elseif startswith(input, "/../")
            input = input[4:end]
            output = _remove_last_segment(output)
        elseif input == "/.."
            input = "/"
            output = _remove_last_segment(output)
        elseif input in (".", "..")
            input = ""
        else
            segment, input = _move_first_segment(input)
            output *= segment
        end
    end
    return output
end

function _has_authority(uri::URIs.URI)
    lowercase(uri.scheme) in URIs.uses_authority && return true
    (!isempty(uri.userinfo) || !isempty(uri.host) || !isempty(uri.port)) &&
        return true
    text = string(uri)
    isempty(uri.scheme) && return startswith(text, "//")
    separator = findfirst(==(':'), text)
    separator === nothing && return false
    return startswith(SubString(text, nextind(text, separator)), "//")
end

function _build_uri(scheme, userinfo, host, port, path, query, authority::Bool)
    output = IOBuffer()
    isempty(scheme) || print(output, scheme, ':')
    if authority
        print(output, "//")
        isempty(userinfo) || print(output, userinfo, '@')
        if occursin(':', host) && !startswith(host, '[')
            print(output, '[', host, ']')
        else
            print(output, host)
        end
        isempty(port) || print(output, ':', port)
    end
    print(output, path)
    isempty(query) || print(output, '?', query)
    return URIs.URI(String(take!(output)))
end

function _normalized_port(scheme::AbstractString, port::AbstractString)
    normalized_scheme = lowercase(scheme)
    if (normalized_scheme == "http" && port == "80") ||
       (normalized_scheme == "https" && port == "443")
        return ""
    end
    return String(port)
end

ResourceId(uri::AbstractString) = ResourceId(URIs.URI(uri))
Base.string(id::ResourceId) = id.text
Base.:(==)(left::ResourceId, right::ResourceId) = left.text == right.text
function Base.isequal(left::ResourceId, right::ResourceId)
    return isequal(left.text, right.text)
end
Base.hash(id::ResourceId, hash::UInt) = Base.hash(id.text, hash)
function Base.show(io::IO, id::ResourceId)
    return print(io, "ResourceId(", repr(string(id)), ")")
end

abstract type Fragment end

struct RootFragment <: Fragment end

struct PointerFragment <: Fragment
    pointer::JSONPointer
end

struct AnchorFragment <: Fragment
    name::String

    function AnchorFragment(name::AbstractString)
        isempty(name) && throw(ArgumentError("an anchor name cannot be empty"))
        return new(String(name))
    end
end

"""An absolute resource reference with a parsed root, pointer, or anchor fragment."""
struct Reference
    resource::ResourceId
    fragment::Fragment
end

function _without_fragment(uri::URIs.URI)
    return _build_uri(
        uri.scheme,
        uri.userinfo,
        uri.host,
        uri.port,
        uri.path,
        uri.query,
        _has_authority(uri),
    )
end

function _fragment(uri::URIs.URI)
    fragment = URIs.unescapeuri(uri.fragment)
    isempty(fragment) && return RootFragment()
    startswith(fragment, '/') && return PointerFragment(JSONPointer(fragment))
    return AnchorFragment(fragment)
end

function Reference(base::ResourceId, reference::AbstractString)
    resolved = URIs.resolvereference(base.uri, URIs.URI(reference))
    return Reference(
        ResourceId(_without_fragment(resolved)),
        _fragment(resolved),
    )
end

struct NodeId
    resource::ResourceId
    pointer::JSONPointer
end

"""A read-only JSON resource with canonical and retrieval identifiers."""
struct Resource{T}
    id::ResourceId
    retrieval::ResourceId
    source::NodeId
    contents::T
    media_type::Union{Nothing,String}

    function Resource(
        id::ResourceId,
        retrieval::ResourceId,
        source::NodeId,
        contents,
        media_type::Union{Nothing,AbstractString},
    )
        frozen = freeze(contents)
        normalized_media_type =
            media_type === nothing ? nothing : String(media_type)
        return new{typeof(frozen)}(
            id,
            retrieval,
            source,
            frozen,
            normalized_media_type,
        )
    end
end

function Resource(
    id::ResourceId,
    contents;
    retrieval::ResourceId = id,
    source::NodeId = NodeId(retrieval, JSONPointer()),
    media_type::Union{Nothing,AbstractString} = nothing,
)
    return Resource(id, retrieval, source, contents, media_type)
end

struct DuplicateResourceError <: Exception
    id::ResourceId
end

function Base.showerror(io::IO, err::DuplicateResourceError)
    return print(
        io,
        "resource ",
        repr(string(err.id)),
        " is already registered",
    )
end

struct MissingResourceError <: Exception
    id::ResourceId
end

function Base.showerror(io::IO, err::MissingResourceError)
    return print(io, "resource ", repr(string(err.id)), " is not registered")
end

struct MissingAnchorError <: Exception
    resource::ResourceId
    anchor::String
end

function Base.showerror(io::IO, err::MissingAnchorError)
    return print(
        io,
        "anchor ",
        repr(err.anchor),
        " is not registered in resource ",
        repr(string(err.resource)),
    )
end

abstract type AbstractRegistry end

"""A registry builder for immutable resources, aliases, and plain-name anchors."""
mutable struct Registry <: AbstractRegistry
    resources::Dict{ResourceId,Resource}
    aliases::Dict{ResourceId,ResourceId}
    anchors::Dict{Tuple{ResourceId,String},NodeId}
    dynamic_anchors::Dict{Tuple{ResourceId,String},NodeId}
    boundaries::Dict{NodeId,NodeId}
end

"""A read-only snapshot of a resource registry."""
struct FrozenRegistry <: AbstractRegistry
    resources::Dict{ResourceId,Resource}
    aliases::Dict{ResourceId,ResourceId}
    anchors::Dict{Tuple{ResourceId,String},NodeId}
    dynamic_anchors::Dict{Tuple{ResourceId,String},NodeId}
    boundaries::Dict{NodeId,NodeId}

    function FrozenRegistry(
        resources,
        aliases,
        anchors,
        dynamic_anchors,
        boundaries,
    )
        return new(
            copy(resources),
            copy(aliases),
            copy(anchors),
            copy(dynamic_anchors),
            copy(boundaries),
        )
    end
end

function freeze(registry::Registry)
    return FrozenRegistry(
        registry.resources,
        registry.aliases,
        registry.anchors,
        registry.dynamic_anchors,
        registry.boundaries,
    )
end

function Base.getproperty(registry::FrozenRegistry, name::Symbol)
    name in (:resources, :aliases, :anchors, :dynamic_anchors, :boundaries) &&
        return copy(getfield(registry, name))
    return getfield(registry, name)
end

function Registry()
    return Registry(
        Dict{ResourceId,Resource}(),
        Dict{ResourceId,ResourceId}(),
        Dict{Tuple{ResourceId,String},NodeId}(),
        Dict{Tuple{ResourceId,String},NodeId}(),
        Dict{NodeId,NodeId}(),
    )
end

function _canonical_id(registry::AbstractRegistry, id::ResourceId)
    return get(getfield(registry, :aliases), id, id)
end

function register!(
    registry::Registry,
    resource::Resource;
    aliases = ResourceId[],
    anchors = Pair{String,JSONPointer}[],
    alias_retrieval::Bool = true,
)
    ids = ResourceId[resource.id]
    alias_retrieval && push!(ids, resource.retrieval)
    append!(ids, aliases)
    unique!(ids)
    for id in ids
        canonical = _canonical_id(registry, id)
        if haskey(registry.resources, canonical) || haskey(registry.aliases, id)
            throw(DuplicateResourceError(id))
        end
    end
    anchor_entries = Pair{Tuple{ResourceId,String},NodeId}[]
    for (name, pointer) in anchors
        normalized_name = AnchorFragment(name).name
        key = (resource.id, normalized_name)
        if haskey(registry.anchors, key) ||
           any(entry -> entry.first == key, anchor_entries)
            throw(ArgumentError("duplicate anchor $(repr(normalized_name))"))
        end
        resolve(resource.contents, pointer)
        push!(anchor_entries, key => NodeId(resource.id, pointer))
    end
    registry.resources[resource.id] = resource
    for id in ids
        id == resource.id && continue
        registry.aliases[id] = resource.id
    end
    for entry in anchor_entries
        registry.anchors[entry.first] = entry.second
    end
    return resource
end

function register_alias!(
    registry::Registry,
    alias::ResourceId,
    target::ResourceId,
)
    registered = resource(registry, target)
    alias == registered.id && return registered.id
    if haskey(registry.resources, alias) || haskey(registry.aliases, alias)
        throw(DuplicateResourceError(alias))
    end
    registry.aliases[alias] = registered.id
    return registered.id
end

function register_anchor!(
    registry::Registry,
    resource_id::ResourceId,
    name::AbstractString,
    pointer::JSONPointer;
    dynamic::Bool = false,
)
    registered = resource(registry, resource_id)
    normalized_name = AnchorFragment(name).name
    key = (registered.id, normalized_name)
    haskey(registry.anchors, key) &&
        throw(ArgumentError("duplicate anchor $(repr(normalized_name))"))
    resolve(registered.contents, pointer)
    node = NodeId(registered.id, pointer)
    registry.anchors[key] = node
    dynamic && (registry.dynamic_anchors[key] = node)
    return node
end

function register_boundary!(registry::Registry, source::NodeId, target::NodeId)
    source == target && return target
    haskey(registry.boundaries, source) && throw(
        ArgumentError(
            "resource boundary $(repr(source)) is already registered",
        ),
    )
    resolve(resource(registry, source.resource).contents, source.pointer)
    resource(registry, target.resource)
    isempty(target.pointer) || throw(
        ArgumentError("a resource boundary target must be a resource root"),
    )
    registry.boundaries[source] = target
    return target
end

function canonical(registry::AbstractRegistry, node::NodeId)
    canonical_id = _canonical_id(registry, node.resource)
    boundaries = getfield(registry, :boundaries)
    normalized =
        canonical_id == node.resource ? node :
        NodeId(canonical_id, node.pointer)
    isempty(boundaries) && return normalized
    current = NodeId(canonical_id, JSONPointer())
    current = get(boundaries, current, current)
    for token in node.pointer
        current = NodeId(current.resource, current.pointer / token)
        current = get(boundaries, current, current)
    end
    return current
end

function resource(registry::AbstractRegistry, id::ResourceId)
    canonical = _canonical_id(registry, id)
    return get(
        () -> throw(MissingResourceError(id)),
        getfield(registry, :resources),
        canonical,
    )
end

function Base.haskey(registry::AbstractRegistry, id::ResourceId)
    return haskey(getfield(registry, :resources), _canonical_id(registry, id))
end

Base.length(registry::AbstractRegistry) = length(getfield(registry, :resources))
Base.isempty(registry::AbstractRegistry) = isempty(getfield(registry, :resources))

struct ResolvedNode{T}
    id::NodeId
    value::T
end

function resolve(registry::AbstractRegistry, reference::Reference)
    registered = resource(registry, reference.resource)
    fragment = reference.fragment
    if fragment isa RootFragment
        id = canonical(registry, NodeId(registered.id, JSONPointer()))
    elseif fragment isa PointerFragment
        id = canonical(registry, NodeId(registered.id, fragment.pointer))
    else
        key = (registered.id, fragment.name)
        id = get(
            () -> throw(MissingAnchorError(registered.id, fragment.name)),
            getfield(registry, :anchors),
            key,
        )
    end
    canonical_resource = resource(registry, id.resource)
    return ResolvedNode(id, resolve(canonical_resource.contents, id.pointer))
end

function dynamic_anchor(
    registry::AbstractRegistry,
    resource_id::ResourceId,
    name::AbstractString,
)
    registered = resource(registry, resource_id)
    return get(
        getfield(registry, :dynamic_anchors),
        (registered.id, String(name)),
        nothing,
    )
end

abstract type AbstractRetriever end

struct RetrievalError <: Exception
    id::ResourceId
    reason::String
end

function Base.showerror(io::IO, err::RetrievalError)
    return print(io, "cannot retrieve ", repr(string(err.id)), ": ", err.reason)
end

struct RetrievedResource
    id::ResourceId
    bytes::Vector{UInt8}
    media_type::Union{Nothing,String}

    function RetrievedResource(
        id::ResourceId,
        bytes::AbstractVector{UInt8},
        media_type::Union{Nothing,AbstractString},
    )
        normalized_media_type =
            media_type === nothing ? nothing : String(media_type)
        return new(id, copy(bytes), normalized_media_type)
    end
end

function Base.getproperty(resource::RetrievedResource, name::Symbol)
    name === :bytes && return copy(getfield(resource, :bytes))
    return getfield(resource, name)
end

function RetrievedResource(
    id::ResourceId,
    bytes::AbstractVector{UInt8};
    media_type::Union{Nothing,AbstractString} = nothing,
)
    return RetrievedResource(id, bytes, media_type)
end

struct DisabledRetriever <: AbstractRetriever end

function retrieve(::DisabledRetriever, id::ResourceId)
    return throw(RetrievalError(id, "external retrieval is disabled"))
end

struct MemoryRetriever <: AbstractRetriever
    resources::Dict{ResourceId,RetrievedResource}

    function MemoryRetriever(resources::Dict{ResourceId,RetrievedResource})
        copied = Dict(
            id =>
                RetrievedResource(value.id, value.bytes, value.media_type)
            for (id, value) in resources
        )
        return new(copied)
    end
end

function Base.getproperty(retriever::MemoryRetriever, name::Symbol)
    name === :resources && return copy(getfield(retriever, :resources))
    return getfield(retriever, name)
end

MemoryRetriever() = MemoryRetriever(Dict{ResourceId,RetrievedResource}())

function MemoryRetriever(resources::AbstractDict)
    normalized = Dict{ResourceId,RetrievedResource}()
    for (raw_id, value) in resources
        id = raw_id isa ResourceId ? raw_id : ResourceId(raw_id)
        if value isa RetrievedResource
            normalized[id] = value
        elseif value isa AbstractString
            normalized[id] =
                RetrievedResource(id, Vector{UInt8}(codeunits(value)))
        elseif value isa AbstractVector{UInt8}
            normalized[id] = RetrievedResource(id, value)
        else
            throw(
                ArgumentError(
                    "memory resources must contain strings, bytes, or RetrievedResource values",
                ),
            )
        end
    end
    return MemoryRetriever(normalized)
end

function retrieve(retriever::MemoryRetriever, id::ResourceId)
    found = get(
        () ->
            throw(RetrievalError(id, "resource is not present in memory")),
        getfield(retriever, :resources),
        id,
    )
    return RetrievedResource(
        found.id,
        found.bytes;
        media_type = found.media_type,
    )
end

struct FileRetriever <: AbstractRetriever
    roots::Vector{String}
    max_bytes::Int

    function FileRetriever(
        roots::AbstractVector{<:AbstractString};
        max_bytes::Integer = 16 * 1024 * 1024,
    )
        max_bytes > 0 || throw(ArgumentError("max_bytes must be positive"))
        normalized = String[]
        for root in roots
            path = realpath(abspath(expanduser(root)))
            isdir(path) || throw(
                ArgumentError("file root $(repr(path)) is not a directory"),
            )
            push!(normalized, path)
        end
        isempty(normalized) &&
            throw(ArgumentError("at least one file root is required"))
        return new(unique(normalized), Int(max_bytes))
    end
end

function FileRetriever(root::AbstractString; kwargs...)
    return FileRetriever([root]; kwargs...)
end

function _is_within(path::String, root::String)
    path == root && return true
    separator = Sys.iswindows() ? '\\' : '/'
    return startswith(path, rstrip(root, separator) * separator)
end

function retrieve(retriever::FileRetriever, id::ResourceId)
    uri = id.uri
    (isempty(uri.scheme) || lowercase(uri.scheme) == "file") ||
        throw(RetrievalError(id, "the URI scheme is not file"))
    isempty(uri.host) ||
        lowercase(uri.host) == "localhost" ||
        throw(RetrievalError(id, "remote file hosts are not allowed"))
    isempty(uri.query) ||
        throw(RetrievalError(id, "file URIs cannot contain a query"))
    path = try
        realpath(abspath(URIs.unescapeuri(uri.path)))
    catch err
        throw(RetrievalError(id, sprint(showerror, err)))
    end
    any(root -> _is_within(path, root), retriever.roots) ||
        throw(RetrievalError(id, "the path is outside the allowed roots"))
    isfile(path) || throw(RetrievalError(id, "the path is not a regular file"))
    bytes = try
        open(path, "r") do io
            filesize(io) <= retriever.max_bytes || throw(
                RetrievalError(
                    id,
                    "the file exceeds the $(retriever.max_bytes)-byte limit",
                ),
            )
            return read(io)
        end
    catch err
        err isa RetrievalError && rethrow()
        throw(RetrievalError(id, sprint(showerror, err)))
    end
    media_type =
        endswith(lowercase(path), ".json") ? "application/schema+json" : nothing
    return RetrievedResource(id, bytes; media_type)
end

end
