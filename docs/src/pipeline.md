# Pipeline and diagnostics

The public stages are separate so applications can inspect or cache them.

- [`OpenAPI.load`](@ref) parses one root document and validates it against the
  official schema for its OAS minor line. It returns an immutable
  [`OpenAPI.SourceDocument`](@ref) with source identity, format, version, and
  source locations.
- [`OpenAPI.check`](@ref) returns structured [`OpenAPI.Diagnostic`](@ref)
  values instead of throwing for document validation errors.
- [`OpenAPI.normalize`](@ref) resolves references and creates an immutable,
  version-neutral [`OpenAPI.NormalizedAPI`](@ref).
- [`OpenAPI.plan`](@ref) creates deterministic Julia model and operation plans
  (a [`OpenAPI.ClientPlan`](@ref); [`OpenAPI.serverplan`](@ref) is the server
  sibling).
- [`OpenAPI.client`](@ref) / [`OpenAPI.server`](@ref) emit source and
  optionally write it to a file.

Every stage accepts the output of any earlier stage — or the original source —
so the short form `OpenAPI.client("openapi.yaml"; ...)` runs the whole
pipeline.

## The stages, end to end

```@example pipeline
using OpenAPI

document = """
openapi: 3.1.0
info: {title: Widgets, version: 1.0.0}
paths:
  /widgets/{id}:
    get:
      operationId: getWidget
      parameters:
        - {name: id, in: path, required: true, schema: {type: integer, format: int64}}
      responses:
        "200":
          description: one widget
          content:
            application/json:
              schema:
                \$ref: "#/components/schemas/Widget"
components:
  schemas:
    Widget:
      type: object
      required: [id, name]
      properties:
        id: {type: integer, format: int64}
        name: {type: string}
        tags: {type: array, items: {type: string}}
"""

source = OpenAPI.load(document)
(source.version.raw, source.format)
```

```@example pipeline
api = OpenAPI.normalize(source)
(api.title, [operation.id for operation in api.operations])
```

```@example pipeline
plan = OpenAPI.plan(api; name = "WidgetsClient")
[(model.name, model.kind) for model in plan.models]
```

```@example pipeline
source_code = OpenAPI.client(plan)
println(join(Iterators.take(eachsplit(source_code, '\n'), 4), '\n'))
println("⋮ (", count('\n', source_code), " lines)")
```

## Diagnostics

Errors use stable diagnostic codes and resource plus JSON Pointer locations
([`OpenAPI.location`](@ref) recovers the position in the original text). JSON
and YAML mappings reject duplicate keys. Parsers reject alias cycles,
non-finite numbers, excessive nesting, and documents that exceed configured
limits.

[`OpenAPI.check`](@ref) collects structural diagnostics without throwing:

```@example pipeline
diagnostics = OpenAPI.check("openapi: 3.1.0\ninfo: {title: Broken, version: 1.0.0}")
foreach(println, diagnostics)
```

## Resource limits

The main limits are:

```julia
OpenAPI.normalize(
    source;
    base_uri = nothing, # identity for inline JSON or YAML
    max_bytes = 16 * 1024 * 1024,
    max_nodes = 1_000_000,
    max_depth = 512,
    max_resources = 256,
    max_diagnostics = 1_000,
)
```

## References

OpenAPI.jl resolves reusable OpenAPI objects and JSON Schema references. It
uses the isolated [`OpenAPI.SchemaEngine`](@ref) module for resource identity,
URI resolution, JSON Pointer, anchors, schema dialects, schema compilation,
and runtime validation.

The schema engine is provisional. It is kept under `src/schema_engine` with no
OpenAPI-specific behavior so it can move to JSONSchema.jl after the API and
implementation have hardened against real OpenAPI documents.

The default retriever has conservative access rules:

- A local root can read relative files under the root file's directory.
- Extra local roots require `file_roots=[...]`.
- A URL root can read same-origin HTTP or HTTPS references.
- Cross-origin references require `allow_remote_refs=true`.
- HTTP redirects are not followed.
- Unsupported URI schemes are rejected.

Pass an `OpenAPI.SchemaEngine.Resources.AbstractRetriever` with `retriever=...`
when an application needs another retrieval policy or an in-memory resource
store. Resource size and count limits still apply.

Non-schema reference cycles are rejected. Recursive JSON Schemas are retained
and compiled normally. OpenAPI 3.0 Reference Object siblings are ignored.
OpenAPI 3.1 and 3.2 `summary` and `description` siblings are applied. Path Item
Reference Object siblings have undefined specification behavior. Strict mode
rejects them. Permissive mode warns and lets local fields override the target.
