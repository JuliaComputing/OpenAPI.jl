# Using OpenAPI.jl

Use this guide when a task needs to inspect an OpenAPI description, generate a
Julia client, or create a basic OpenAPI document from Julia declarations.

## Read and inspect a description

```julia
using OpenAPI

source = OpenAPI.load("openapi.yaml")
println(source.version)

diagnostics = OpenAPI.check("openapi.yaml")
foreach(println, diagnostics)

api = OpenAPI.normalize(source)
println(api.title)
println(length(api.operations))
```

Use `using HTTP` before loading an HTTP or HTTPS URL.

## Generate a Julia client

```julia
using OpenAPI, HTTP

OpenAPI.client(
    "https://example.com/openapi.json";
    name = "ExampleClient",
    path = "ExampleClient.jl",
)
```

The target environment for `ExampleClient.jl` must contain OpenAPI.jl, HTTP.jl,
and JSON.jl.

```julia
include("ExampleClient.jl")

client = ExampleClient.Client("https://api.example.com")
ExampleClient.authorization!(client, ENV["EXAMPLE_TOKEN"])
result = ExampleClient.list_widgets(; client)
```

Use `ExampleClient.ABSENT` for an omitted optional value. Use `nothing` only
for an explicit nullable value. Pass `with_http_info=true` when status and
headers are needed.

## External references

Local roots may read relative references from their directory. Add explicit
roots when needed:

```julia
api = OpenAPI.normalize(
    "specs/root.yaml";
    file_roots = ["schemas", "shared-specs"],
)
```

A URL root permits same-origin references. Use `allow_remote_refs=true` only
when the document is trusted to select cross-origin resources. For a controlled
resource store, pass an `OpenAPI.SchemaEngine.Resources.AbstractRetriever` as
`retriever`.

## Strict and permissive modes

Keep `strict=true` for normal work. If a public description uses a known
ecosystem extension, inspect the diagnostics before using permissive mode:

```julia
api = OpenAPI.normalize(source; strict = false)
foreach(println, api.diagnostics)
```

Permissive mode does not bypass unsupported feature checks. Client generation
still fails for OAS 3.2 `querystring` parameters and streaming or positional
`itemSchema`, `itemEncoding`, and `prefixEncoding` behavior.

## Custom body codecs

```julia
ExampleClient.codec!(
    client,
    "application/cbor";
    encode = (value, media_type) -> encode_cbor(value),
    decode = (bytes, media_type) -> decode_cbor(bytes),
)
```

Use this mechanism for XML and other representations that do not have a
built-in codec.

## Create a document

```julia
using OpenAPI, JSON

operations = [
    OpenAPI.Operation(
        id = "get_item",
        method = :GET,
        path = "/items/{id}",
        params = [OpenAPI.Param("id", :path, Int)],
        responsetype = Item,
    ),
]

document = OpenAPI.document(operations; title = "Items", version = "1.0.0")
println(JSON.json(document; pretty = 2))
```

This authoring API covers common Julia endpoint declarations. It is not a
general builder for every OpenAPI Object. Build advanced documents as JSON-like
objects and pass them through `OpenAPI.validate` or `OpenAPI.normalize`.

## Verify generated output

At minimum:

1. Include the generated source in a fresh module.
2. Exercise a real or local HTTP endpoint.
3. Inspect serialized path, query, header, cookie, and body values.
4. Test a documented success and a documented error response.
5. Keep request and response schema validation enabled.

See `README.md` for the detailed feature and support matrix.
