# Documents from Julia code

The authoring API is intentionally smaller than the ingestion and client
pipeline. It maps common Julia endpoint declarations to an OpenAPI 3.2.0
document: describe each endpoint as an [`OpenAPI.Operation`](@ref) and pass
the collection to [`OpenAPI.document`](@ref).

```@example authoring
using OpenAPI, JSON

struct Widget
    id::Int
    tags::Vector{String}
end

operations = [
    OpenAPI.Operation(
        id = "get_widget",
        method = :GET,
        path = "/v1/widgets/{id}",
        params = [
            OpenAPI.Param("id", :path, Int),
            OpenAPI.Param("verbose", :query, Bool; required = false),
        ],
        responsetype = Widget,
    ),
]

document = OpenAPI.document(
    operations;
    title = "Widgets",
    version = "1.0.0",
)

println(JSON.json(document; pretty = 2))
```

Named struct types encountered in parameter, body, and response types are
collected under `components/schemas` and referenced by `$ref`;
[`OpenAPI.schemaof`](@ref) documents the exact Julia-type-to-schema mapping.

The result is a plain JSON object, so the same document can be served by an
application, written to a file, or fed straight back into the generation
pipeline ([`OpenAPI.client`](@ref) accepts in-memory documents).

OpenAPI.jl does not depend on a server framework. Framework packages can add
optional [`OpenAPI.operations`](@ref) and [`OpenAPI.register!`](@ref) methods
to expose their routes as `Operation`s and serve the generated document.
Servo.jl provides its OpenAPI adapter from a downstream package extension.
