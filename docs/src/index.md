# OpenAPI.jl

OpenAPI.jl reads [OpenAPI](https://www.openapis.org/) descriptions and
generates single-file, typed Julia HTTP clients and server stubs. It also
provides a smaller API for creating an OpenAPI document from declared Julia
endpoints.

Three pieces:

1. **Client generation** — [`OpenAPI.client`](@ref) turns an OpenAPI 3.0, 3.1,
   or 3.2 document (built in-process, read from JSON or YAML, or fetched from a
   running app) into a deterministic single-file Julia client. Generated
   modules use HTTP.jl for transport and JSON.jl plus OpenAPI's provisional
   schema engine for typed, validated request and response handling.
2. **Server generation** — [`OpenAPI.server`](@ref) turns the same documents
   into a deterministic single-file server-stub module: typed request decoding,
   response validation and encoding, and a `register!(router, impl)` entry
   point that mounts handler functions you implement onto a framework router.
3. **Document generation** — describe endpoints as [`OpenAPI.Operation`](@ref)s
   and get a valid OpenAPI 3.2.0 document. Framework packages can add router
   adapters through the [`OpenAPI.operations`](@ref) and
   [`OpenAPI.register!`](@ref) extension seams.

The pipeline supports OpenAPI 3.0.x, 3.1.x, and 3.2.x. It parses JSON and
YAML, resolves references, validates the document, normalizes version
differences, plans Julia types, and emits deterministic source code.
OpenAPI.jl supports Julia 1.10 LTS and later Julia 1.x releases.

OpenAPI.jl does not export names. Use its API through the `OpenAPI` namespace.

!!! note "Upgrading from 0.2.x"
    OpenAPI.jl 0.2.x was the runtime library consumed by code that the Java
    [openapi-generator](https://openapi-generator.tech/) `julia-client` /
    `julia-server` targets produced. 1.0 replaces that model with the native
    generator described here, and the 0.2.x runtime API is removed — a
    breaking change. See [Migrating from OpenAPI.jl 0.2.x to 1.0](migration.md).

## Installation

```julia-repl
pkg> add OpenAPI
```

A generated module additionally imports `HTTP` and `JSON` (plus the standard
libraries `Base64`, `Dates`, and `UUIDs`). Add those two packages to the
environment that will include the generated file.

## Generate a client

```julia
using OpenAPI, HTTP

OpenAPI.client(
    "https://example.com/openapi.yaml";
    name = "ExampleClient",
    path = "ExampleClient.jl",
)
```

```julia
include("ExampleClient.jl")

client = ExampleClient.Client("https://api.example.com")

# Each operationId becomes a Julia function. Path parameters are positional,
# other parameters are keywords.
result = ExampleClient.get_widget("widget-123"; verbose = true, client)
```

[Generating clients](clients.md) covers the full calling convention, error
handling, and content negotiation.

## Generate a server

```julia
using OpenAPI, HTTP

OpenAPI.server(
    "https://example.com/openapi.yaml";
    framework = :HTTP,
    name = "ExampleServer",
    path = "ExampleServer.jl",
)
```

The generated module header lists every handler signature to implement;
`ExampleServer.register!(router, Handlers)` mounts them on an `HTTP.Router`.
[Generating servers](servers.md) covers the handler contract, middleware, and
request decoding behavior.

## How the documentation is organized

- [Migrating from 0.2.x](migration.md) — what changed relative to the
  openapi-generator lane, and how to move over.
- [Generating clients](clients.md), [Streaming and codecs](streaming.md), and
  [Security](security.md) — generating a client and everything the generated
  client can do.
- [Generating servers](servers.md) — server stubs, the handler contract, and
  `register!`.
- [Documents from Julia code](documents.md) — the authoring API.
- [Pipeline and diagnostics](pipeline.md) — the staged public pipeline,
  diagnostics, resource limits, and reference resolution.
- [Generated models](models.md) — how JSON Schemas become Julia types and what
  validation guarantees hold.
- [Generated modules and the runtime contract](artifacts.md) — why generated
  files are versioned build products and when to regenerate.
- [Support boundary](boundary.md) — what is supported, deferred, and rejected,
  and what strict mode means.
- [API reference](reference.md) — docstrings for every public name.

## Specification sources

OpenAPI behavior follows the normative
[OpenAPI 3.0.4](https://spec.openapis.org/oas/v3.0.4.html),
[OpenAPI 3.1.1](https://spec.openapis.org/oas/v3.1.1.html), and
[OpenAPI 3.2.0](https://spec.openapis.org/oas/v3.2.0.html) specifications.
The files in the repository's `schemas/` directory are official structural
schemas published by the OpenAPI Initiative. The normative text remains
authoritative when a published schema differs from it.
