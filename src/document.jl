const METHODS = (:GET, :POST, :PUT, :DELETE, :PATCH, :HEAD, :OPTIONS, :TRACE, :QUERY)

"""
    OpenAPI.Param(name, location, type; required=true)

One path or query parameter of an [`Operation`](@ref): `location` is `:path` or
`:query`, `type` is the Julia type the value coerces to (drives the emitted
schema).
"""
struct Param
    name::String
    location::Symbol
    type::Type
    required::Bool

    function Param(
        name::AbstractString,
        location::Symbol,
        type::Type = String;
        required::Bool = true,
    )
        location in (:path, :query) || throw(
            ArgumentError(
                "Param `$name`: location must be :path or :query, got :$location",
            ),
        )
        location == :path &&
            !required &&
            throw(ArgumentError("Param `$name`: path parameters are always required"))
        return new(String(name), location, type, required)
    end
end

"""
    OpenAPI.Operation(; id, method, path, kw...)

A framework-neutral description of one endpoint, the input to
[`OpenAPI.document`](@ref). Anything that can describe its endpoints as
`Operation`s can use the same document-generation path.

Keywords:
- `id::String` — the `operationId` (also the generated client's function name)
- `method::Symbol` — `:GET`, `:POST`, … (`$(METHODS)`)
- `path::String` — `/segment/{param}` template; placeholders must match the
  `:path` params exactly
- `summary=""` — human description
- `params=Param[]` — path/query parameters
- `bodytype=nothing` — Julia type of the request body, or `nothing` for none
- `responsetype=nothing` — no success response body (status 200); the *type*
  `Nothing` means 204 No Content, `Any` means unconstrained JSON, and a
  `Union{Nothing, T}` emits both 204 and a 200 with `T`'s schema
- `contenttype="application/json"` — media type for body/response content
- `secured=false` — whether the operation requires authentication (emitted as a
  bearer security requirement)
"""
struct Operation
    id::String
    method::Symbol
    path::String
    summary::String
    params::Vector{Param}
    bodytype::Union{Nothing,Type}
    responsetype::Any
    contenttype::String
    secured::Bool
end

function Operation(;
    id::AbstractString,
    method::Symbol,
    path::AbstractString,
    summary::AbstractString = "",
    params::Vector{Param} = Param[],
    bodytype::Union{Nothing,Type} = nothing,
    responsetype = nothing,
    contenttype::AbstractString = "application/json",
    secured::Bool = false,
)
    method in METHODS || throw(
        ArgumentError(
            "operation `$id`: unsupported method `$method`; expected one of $(join(METHODS, ", "))",
        ),
    )
    startswith(path, "/") ||
        throw(ArgumentError("operation `$id`: path must start with '/': `$path`"))
    placeholders = pathplaceholders(path)
    pathnames = [p.name for p in params if p.location == :path]
    for ph in placeholders
        ph in pathnames || throw(
            ArgumentError(
                "operation `$id`: path parameter `{$ph}` in `$path` has no matching Param",
            ),
        )
    end
    for p in pathnames
        p in placeholders || throw(
            ArgumentError(
                "operation `$id`: Param `$p` is a path parameter but `$path` has no `{$p}` segment",
            ),
        )
    end
    responsetype === nothing ||
        responsetype isa Type ||
        throw(ArgumentError("operation `$id`: responsetype must be a Type or nothing"))
    return Operation(
        String(id),
        method,
        String(path),
        String(summary),
        params,
        bodytype,
        responsetype,
        String(contenttype),
        secured,
    )
end

function pathplaceholders(path::AbstractString)
    names = String[]
    for seg in split(path, '/'; keepempty = false)
        m = match(r"^\{(\w+)\}$", seg)
        if m !== nothing
            name = String(m.captures[1])
            name in names &&
                throw(ArgumentError("duplicate path parameter `{$name}` in `$path`"))
            push!(names, name)
        elseif occursin('{', seg) || occursin('}', seg)
            throw(
                ArgumentError(
                    "malformed segment `$seg` in `$path`: a path parameter must be a full segment like `{name}`",
                ),
            )
        end
    end
    return names
end

# A small framework-neutral default error envelope.
errorschema() = obj(
    "type" => "object",
    "properties" => obj(
        "error" => obj(
            "type" => "object",
            "properties" => obj(
                "message" => obj("type" => "string"),
                "code" => obj("type" => "integer"),
            ),
        ),
    ),
)

"""
    OpenAPI.document(operations; title="API", version="0.1.0", description="", servers=String[])
        -> JSON.Object

Build a valid OpenAPI $(OPENAPI_VERSION) document from a vector of
[`Operation`](@ref)s. Named struct types encountered in parameter, body, and
response types are collected under `components/schemas` and referenced by
`\$ref`. Serialize with `JSON.json(doc)` (or `JSON.json(doc; pretty=2)`).

Framework packages can add router-specific methods without becoming an OpenAPI
dependency.
"""
function document(
    ops::Vector{Operation};
    title::AbstractString = "API",
    version::AbstractString = "0.1.0",
    description::AbstractString = "",
    servers::Vector{String} = String[],
)
    reg = SchemaRegistry()
    paths = JSON.Object{String,Any}()
    ids = Set{String}()
    anysecured = false
    for op in ops
        id = op.id
        i = 2
        while id in ids
            id = string(op.id, "_", i)
            i += 1
        end
        push!(ids, id)
        haskey(paths, op.path) || (paths[op.path] = JSON.Object{String,Any}())
        item = paths[op.path]
        methodkey = lowercase(string(op.method))
        haskey(item, methodkey) &&
            throw(ArgumentError("duplicate operation for $(op.method) $(op.path)"))
        o = obj("operationId" => id)
        isempty(op.summary) || (o["summary"] = op.summary)
        if !isempty(op.params)
            parameters = Any[]
            for p in op.params
                parameter = obj(
                    "name" => p.name,
                    "in" => string(p.location),
                    "required" => p.required,
                    "schema" => schemaof(reg, p.type),
                )
                p.location === :query && p.type <: AbstractVector &&
                    (parameter["explode"] = false)
                push!(parameters, parameter)
            end
            o["parameters"] = parameters
        end
        if op.bodytype !== nothing
            o["requestBody"] = obj(
                "required" => true,
                "content" =>
                    obj(op.contenttype => obj("schema" => schemaof(reg, op.bodytype))),
            )
        end
        responses = JSON.Object{String,Any}()
        rt = op.responsetype
        if rt === nothing
            responses["200"] = obj("description" => "success")
        else
            if rt === Nothing
                responses["204"] = obj("description" => "no content")
            elseif Nothing <: rt
                responses["204"] = obj("description" => "no content")
                inner = Union{filter(t -> t !== Nothing, uniontypes(rt))...}
                responses["200"] = obj(
                    "description" => "success",
                    "content" =>
                        obj(op.contenttype => obj("schema" => schemaof(reg, inner))),
                )
            else
                responses["200"] = obj(
                    "description" => "success",
                    "content" =>
                        obj(op.contenttype => obj("schema" => schemaof(reg, rt))),
                )
            end
        end
        responses["default"] = obj(
            "description" => "unexpected error",
            "content" => obj("application/json" => obj("schema" => errorschema())),
        )
        o["responses"] = responses
        if op.secured
            o["security"] = Any[obj("bearerAuth" => String[])]
            anysecured = true
        end
        item[methodkey] = o
    end
    doc = obj("openapi" => OPENAPI_VERSION)
    info = obj("title" => String(title), "version" => String(version))
    isempty(description) || (info["description"] = String(description))
    doc["info"] = info
    isempty(servers) || (doc["servers"] = Any[obj("url" => s) for s in servers])
    doc["paths"] = paths
    components = JSON.Object{String,Any}()
    isempty(reg.schemas) || (components["schemas"] = reg.schemas)
    anysecured && (
        components["securitySchemes"] =
            obj("bearerAuth" => obj("type" => "http", "scheme" => "bearer"))
    )
    isempty(components) || (doc["components"] = components)
    return doc
end
