# Emitted at the top of every generated client module. The protocol machinery
# lives in OpenAPI.Runtime; generated modules import the names their models and
# operations use, extending only _decode/_encode/_form_fields with methods on
# their own (module-local) model types.
const GENERATED_CLIENT_IMPORTS = raw"""
const SchemaEngine = OpenAPI.SchemaEngine
import OpenAPI.Runtime:
    ABSENT, Absent, AbstractCredential, ApiError, ApiKeyCredential, ApiResponse,
    BasicCredential, BearerCredential, DecodeError, HttpCredential,
    MultipartPartHeaders, MutualTLSCredential, SchemaValidationError,
    UnexpectedBody, UnexpectedContentType, UnsupportedMediaType, Upload,
    _decode, _encode, _form_fields, _object, _required, _request,
    _schema_valid, _validate_schema
"""

# Emitted after the generated module's `_SPEC` constant. These forwarders keep
# the public surface of a generated module (Client(), DEFAULT_CLIENT,
# server!, credential!, ...) while delegating to OpenAPI.Runtime. They are
# deliberately module-local functions, not methods added to Runtime generics,
# so independently generated modules never overwrite each other.
const GENERATED_CLIENT_GLUE = raw"""
const SERVER = _SPEC.server

Client(server::Union{Nothing,AbstractString} = nothing; kwargs...) =
    Runtime.Client(_SPEC, server; kwargs...)
const DEFAULT_CLIENT = Runtime.Client(_SPEC; _default = true)

credential!(client::Runtime.Client, name::AbstractString, credential::AbstractCredential) =
    Runtime.credential!(client, name, credential)
credential!(name::AbstractString, credential::AbstractCredential) =
    Runtime.credential!(DEFAULT_CLIENT, name, credential)
clearcredential!(client::Runtime.Client, name::AbstractString) =
    Runtime.clearcredential!(client, name)
clearcredential!(name::AbstractString) = Runtime.clearcredential!(DEFAULT_CLIENT, name)
server!(client::Runtime.Client, server::Union{Nothing,AbstractString}) =
    Runtime.server!(client, server)
server!(server::Union{Nothing,AbstractString}) = Runtime.server!(DEFAULT_CLIENT, server)
server_index!(client::Runtime.Client, index::Integer) = Runtime.server_index!(client, index)
server_index!(index::Integer) = Runtime.server_index!(DEFAULT_CLIENT, index)
server_name!(client::Runtime.Client, name::Union{Nothing,AbstractString}) =
    Runtime.server_name!(client, name)
server_name!(name::Union{Nothing,AbstractString}) = Runtime.server_name!(DEFAULT_CLIENT, name)
server_variable!(client::Runtime.Client, name::AbstractString, value::AbstractString) =
    Runtime.server_variable!(client, name, value)
server_variable!(name::AbstractString, value::AbstractString) =
    Runtime.server_variable!(DEFAULT_CLIENT, name, value)
codec!(client::Runtime.Client, media_type::AbstractString; kwargs...) =
    Runtime.codec!(client, media_type; kwargs...)
codec!(media_type::AbstractString; kwargs...) =
    Runtime.codec!(DEFAULT_CLIENT, media_type; kwargs...)
authorization!(client::Runtime.Client, token::Union{Nothing,AbstractString}) =
    Runtime.authorization!(client, token)
authorization!(token::Union{Nothing,AbstractString}) =
    Runtime.authorization!(DEFAULT_CLIENT, token)
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
    indices = Dict{String,Int}()
    index = 0
    for model in plan.models
        index += 1
        indices[model.name] = index
    end
    return indices
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
    aliases = Set{String}()
    for model in plan.models
        model.kind === :alias && push!(aliases, model.name)
    end
    edges = Dict{String,Vector{String}}()
    for model in plan.models
        model.kind === :alias || continue
        edges[model.name] =
            _model_references(something(model.alias, ""), aliases)
    end
    function reaches(start, current, seen)
        current in seen && return false
        push!(seen, current)
        for target in get(edges, current, String[])
            target == start && return true
            reaches(start, target, seen) && return true
        end
        return false
    end
    cyclic = Set{String}()
    for name in aliases
        reaches(name, name, Set{String}()) && push!(cyclic, name)
    end
    return cyclic
end

function _model_types(model::ModelPlan, wrapped_aliases)
    if model.kind === :object
        types = String[]
        sizehint!(
            types,
            length(model.fields) + (model.additional_type === nothing ? 0 : 1),
        )
        for field in model.fields
            push!(types, field.type)
        end
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
    concrete = Set{String}()
    for model in plan.models
        model.kind === :alias || push!(concrete, model.name)
    end
    union!(concrete, wrapped_aliases)
    targets = copy(wrapped_aliases)
    index = 0
    for model in plan.models
        index += 1
        for type in _model_types(model, wrapped_aliases)
            for target in _model_references(type, concrete)
                get(indices, target, 0) > index && push!(targets, target)
            end
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

# Spec `description` fields, carried through planning, become the generated
# model's docstring: the schema's own description plus one bullet per
# documented field. Models with no descriptions get no docstring.
function _model_docstring(model::ModelPlan)
    parts = String[]
    model.description === nothing || push!(parts, model.description)
    documented = [field for field in model.fields if field.description !== nothing]
    isempty(documented) || push!(
        parts,
        join(
            ("- `" * field.name * "`: " * field.description for field in documented),
            "\n",
        ),
    )
    isempty(parts) && return nothing
    return "    " * model.name * "\n\n" * join(parts, "\n\n")
end

function _emit_model(
    io::IO,
    model::ModelPlan,
    index,
    indices,
    abstract_targets,
    wrapped_aliases,
)
    doc = _model_docstring(model)
    doc === nothing || println(io, "@doc ", repr(doc))
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
        println(io, "    _openapi_validate && _validate_schema(_SPEC, ", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
        println(io, "    return ", model.name, "(_decode(", type, ", value, _openapi_validate))")
        println(io, "end")
        println(io, "function _encode(value::", model.name, ")")
        println(io, "    output = _encode(value.value)")
        println(io, "    return _validate_schema(_SPEC, ", schema, ", output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
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
        println(io, "    _openapi_validate && _validate_schema(_SPEC, ", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
        println(io, "    return ", model.name, "(_decode(", model.alias, ", value, _openapi_validate))")
        println(io, "end")
        println(io, "function _encode(value::", model.name, ")")
        println(io, "    output = _encode(value.value)")
        println(io, "    return _validate_schema(_SPEC, ", schema, ", output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
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
            println(io, "    _openapi_validate && _validate_schema(_SPEC, ", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
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
            println(io, "    !_openapi_validate || _schema_valid(_SPEC, selected[2], value; direction = ", direction, ") || throw(DecodeError(\"discriminator-selected schema did not validate for ", model.name, "\"))")
            println(io, "    return ", model.name, "(_decode(selected[1], value, _openapi_validate))")
            println(io, "end")
        else
            println(io, "_decode(::Type{", model.name, "}, value) = _decode(", model.name, ", value, true)")
            println(io, "function _decode(::Type{", model.name, "}, value, _openapi_validate::Bool)")
            println(io, "    _openapi_validate && _validate_schema(_SPEC, ", schema, ", value, ", repr("decoding " * model.name), "; direction = ", direction, ")")
            "Nothing" in model.values && println(
                io,
                "    value === nothing && return ",
                model.name,
                "(nothing)",
            )
            println(io, "    matches = Any[]")
            for (node, type) in model.variants
                descriptor = _schema_descriptor(node)
                println(io, "    if !_openapi_validate || _schema_valid(_SPEC, ", descriptor, ", value; direction = ", direction, ")")
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
        println(io, "    return _validate_schema(_SPEC, ", schema, ", output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
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
    println(io, "    _openapi_validate && _validate_schema(_SPEC, ", schema, ", _openapi_raw, ", repr("decoding " * model.name), "; direction = ", direction, ")")
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
    known = String[]
    sizehint!(known, length(model.fields))
    for field in model.fields
        push!(known, field.wire_name)
    end
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
    assignments = String[]
    sizehint!(
        assignments,
        length(model.fields) + (model.additional_type === nothing ? 0 : 1),
    )
    for field in model.fields
        push!(assignments, string(field.name, " = _openapi_field_", field.name))
    end
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
    println(io, "    return _validate_schema(_SPEC, ", schema, ", _openapi_output, ", repr("encoding " * model.name), "; direction = ", direction, ")")
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
    # A standard dialect round-trips through its name so the runtime stays the
    # single owner of its flag semantics; only vocabulary-customized dialects
    # bake their flags, and those go through the keyword constructor so a
    # struct-field reorder can never silently reassign them.
    get(SchemaEngine.DIALECTS, value.name, nothing) === value &&
        return "SchemaEngine.dialect(" * repr(value.name) * ")"
    return "SchemaEngine.Dialect(; " * join(
        (
            "name = " * repr(value.name),
            "uri = " * repr(value.uri),
            "id_keyword = " * repr(value.id_keyword),
            "ref_siblings = " * repr(value.ref_siblings),
            "modern_items = " * repr(value.modern_items),
            "unevaluated = " * repr(value.unevaluated),
            "dynamic_refs = " * repr(value.dynamic_refs),
            "recursive_refs = " * repr(value.recursive_refs),
            "applicator = " * repr(value.applicator),
            "validation = " * repr(value.validation),
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
            "(media_type = " * repr(entry.first) *
            ", type = " * entry.second *
            ", schema = " *
            _schema_descriptor(_schema_node(source.schema)) *
            ", encodings = " * encoded *
            ", fields = " * fields * ")",
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
            "(name = " * repr(name) *
            ", scopes = " * _julia_literal(scopes) * ")" for
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
            "client::Runtime.Client = DEFAULT_CLIENT",
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
    documented = Pair{String,String}[
        parameter.name => parameter.parameter.description
        for parameter in operation.parameters
        if parameter.parameter.description !== nothing
    ]
    if operation.request_body !== nothing &&
       operation.request_body.body.description !== nothing
        push!(documented, "body" => operation.request_body.body.description)
    end
    isempty(documented) || (doc *= "\n\n" * join(
        ("- `" * name * "`: " * description for (name, description) in documented),
        "\n",
    ))
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

# Emitted before the private Runtime imports of every generated module so a
# contract mismatch fails at load time with regeneration guidance instead of
# erroring (or silently misbehaving) deep inside the runtime.
function _emit_contract_guard(io::IO)
    println(io, "const Runtime = OpenAPI.Runtime")
    println(
        io,
        "Runtime.require_contract(",
        Runtime.CONTRACT_VERSION,
        ", ",
        repr(PACKAGE_VERSION),
        ")\n",
    )
end

function _generate(plan::ClientPlan)
    io = IOBuffer()
    println(
        io,
        "# Generated by OpenAPI.jl v",
        PACKAGE_VERSION,
        " from ",
        repr(plan.api.title),
        " version ",
        repr(plan.api.api_version),
        ". Do not edit.",
    )
    println(io, "module ", plan.module_name, "\n")
    println(io, "using HTTP, JSON, OpenAPI, Base64, Dates, UUIDs")
    plan.datetime === :zoned && println(io, "using TimeZones")
    _emit_contract_guard(io)
    print(io, GENERATED_CLIENT_IMPORTS, '\n')
    _emit_security(io, plan)
    _emit_schema_data(io, plan)
    println(io, "const _SPEC = Runtime.Spec(;")
    println(io, "    security_schemes = _SECURITY_SCHEMES,")
    println(io, "    resources = _SCHEMA_RESOURCE_DATA,")
    println(io, "    roots = _SCHEMA_ROOT_DATA,")
    println(io, "    dialects = _SCHEMA_DIALECT_DATA,")
    println(io, "    directional_required = _SCHEMA_DIRECTIONAL_REQUIRED,")
    println(io, "    default_server = ", repr(_default_server(plan.api)), ",")
    println(io, ")\n")
    print(io, GENERATED_CLIENT_GLUE, '\n')

    indices = _model_indices(plan)
    wrapped_aliases = _cyclic_aliases(plan)
    abstract_targets = _forward_abstracts(plan, wrapped_aliases)
    for target in sort(collect(abstract_targets))
        println(io, "abstract type Abstract", target, " end")
    end
    isempty(abstract_targets) || println(io)
    index = 0
    for model in plan.models
        index += 1
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
