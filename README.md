# OpenAPI.jl

[![Stable docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliacomputing.github.io/OpenAPI.jl/stable/)
[![Dev docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliacomputing.github.io/OpenAPI.jl/dev/)
[![CI](https://github.com/JuliaComputing/OpenAPI.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaComputing/OpenAPI.jl/actions/workflows/CI.yml)

OpenAPI.jl reads OpenAPI descriptions and generates single-file, typed Julia
HTTP clients and server stubs. It also provides a smaller API for creating an
OpenAPI document from declared Julia endpoints.

The pipeline supports OpenAPI 3.0.x, 3.1.x, and 3.2.x. It parses JSON
and YAML, resolves references, validates the document, normalizes version
differences, plans Julia types, and emits deterministic source code.
OpenAPI.jl supports Julia 1.10 LTS and later Julia 1.x releases.

OpenAPI.jl does not export names. Use its API through the `OpenAPI` namespace.

Upgrading from 0.2.x — the runtime library used by openapi-generator's
`julia-client`/`julia-server` targets — is a breaking change; see
[MIGRATION.md](MIGRATION.md). 0.2.x maintenance continues on the
[`release-0.2`](https://github.com/JuliaComputing/OpenAPI.jl/tree/release-0.2)
branch.

**[The documentation](https://juliacomputing.github.io/OpenAPI.jl/stable/)**
covers the full calling conventions, streaming, security, the staged pipeline,
generated model behavior, the generated-code contract, and the API reference.

## Generate a client

Load `HTTP` before reading a URL. Local files and inline JSON or YAML do not
need `HTTP` during generation.

```julia
using OpenAPI, HTTP

OpenAPI.client(
    "https://example.com/openapi.yaml";
    name = "ExampleClient",
    path = "ExampleClient.jl",
)
```

The generated file imports `OpenAPI`, `HTTP`, and `JSON`; add those three
dependencies to the environment that includes it.

```julia
include("ExampleClient.jl")

client = ExampleClient.Client("https://api.example.com")

# Each operationId becomes a Julia function. Path parameters are positional.
# Other parameters are keywords. A required request body is the last positional
# argument. Pass `client=client` to avoid shared global configuration.
result = ExampleClient.get_widget("widget-123"; verbose = true, client)
```

## Generate a server

The same document generates a server-stub module: implement one handler
function per operation (the generated module header lists every expected
signature) and mount them on a router.

```julia
using OpenAPI, HTTP

OpenAPI.server(
    "https://example.com/openapi.yaml";
    framework = :HTTP,
    name = "ExampleServer",
    path = "ExampleServer.jl",
)
```

```julia
include("ExampleServer.jl")

module Handlers
using HTTP
get_widget(request, id; verbose = false) = lookup_widget(id; verbose)
delete_widget(request, id) = nothing        # documented 204 -> empty 204
end

router = HTTP.Router()
ExampleServer.register!(router, Handlers; path_prefix = "/v1")
server = HTTP.serve!(router, "127.0.0.1", 8080)
```

Requests are decoded and validated before handlers run; return values are
validated and encoded from the documented responses. Generated stubs do not
authenticate requests — apply a `middleware` for that.

## Create a document from Julia declarations

```julia
using OpenAPI, JSON

operations = [
    OpenAPI.Operation(
        id = "get_widget",
        method = :GET,
        path = "/v1/widgets/{id}",
        params = [OpenAPI.Param("id", :path, Int)],
        responsetype = Widget,
    ),
]

document = OpenAPI.document(operations; title = "Widgets", version = "1.0.0")
write("openapi.json", JSON.json(document; pretty = 2))
```

## Specification sources

OpenAPI behavior follows the normative
[OpenAPI 3.0.4](https://spec.openapis.org/oas/v3.0.4.html),
[OpenAPI 3.1.1](https://spec.openapis.org/oas/v3.1.1.html), and
[OpenAPI 3.2.0](https://spec.openapis.org/oas/v3.2.0.html) specifications.
The files in `schemas/` are official structural schemas. The normative text
remains authoritative when a published schema differs from it. Their Apache
License 2.0 text is included in [`schemas/LICENSE`](schemas/LICENSE).
