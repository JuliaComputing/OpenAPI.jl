# OpenAPI.jl

OpenAPI.jl reads OpenAPI descriptions and generates single-file, typed Julia
HTTP clients. It also provides a smaller API for creating an OpenAPI document
from declared Julia endpoints.

The client pipeline supports OpenAPI 3.0.x, 3.1.x, and 3.2.x. It parses JSON
and YAML, resolves references, validates the document, normalizes version
differences, plans Julia types, and emits deterministic source code.

Generated schema graphs use content-derived resource identifiers. Local paths,
source URL userinfo, and source URL query strings are not embedded in generated
files. A relative Server Object still depends on the public scheme, host, and
path of the source URL because that location is part of the OpenAPI resolution
rule.

OpenAPI.jl does not export names. Use its API through the `OpenAPI` namespace.

## Generate a client

Load `HTTP` before reading a URL. Local files and inline JSON or YAML do not
need `HTTP` during generation.

```julia
using OpenAPI, HTTP

source = OpenAPI.load("https://example.com/openapi.yaml")
api = OpenAPI.normalize(source)
plan = OpenAPI.plan(api; name = "ExampleClient")
OpenAPI.client(plan; path = "ExampleClient.jl")
```

The short form runs the same pipeline:

```julia
using OpenAPI, HTTP

OpenAPI.client(
    "https://example.com/openapi.yaml";
    name = "ExampleClient",
    path = "ExampleClient.jl",
)
```

The generated file imports `OpenAPI`, `HTTP`, and `JSON`. It also imports the
Julia standard libraries `Base64`, `Dates`, and `UUIDs`. Add the three package
dependencies to the environment that will include the generated file.

```julia
include("ExampleClient.jl")

client = ExampleClient.Client(
    "https://api.example.com";
    headers = ["User-Agent" => "my-app/1.0"],
)

# Each operationId becomes a Julia function. Path parameters are positional.
# Other parameters are keywords. A required request body is the last positional
# argument. Pass `client=client` to avoid shared global configuration.
result = ExampleClient.get_widget("widget-123"; verbose = true, client)
```

Optional model fields use `ExampleClient.Absent`, not `nothing`. This keeps a
missing value distinct from an explicit JSON `null`.

```julia
model = ExampleClient.WidgetInput(
    name = "example",
    description = ExampleClient.ABSENT,
)
```

Pass `with_http_info=true` to receive an `ApiResponse` with the status, raw
headers, decoded documented headers, and typed body. A non-2xx response throws
`ApiError`. The error keeps the raw body even when documented error decoding
fails.

## Generate a server

The same document generates a server-stub module. The document stays the
source of truth: generate the client and the server from one specification and
implement one handler function per operation.

```julia
using OpenAPI, HTTP

OpenAPI.server(
    "https://example.com/openapi.yaml";
    framework = :HTTP,
    name = "ExampleServer",
    path = "ExampleServer.jl",
)
```

`framework = :HTTP` (the default, available when HTTP.jl is loaded) targets
`HTTP.Router`. Server framework packages add their own emitters through the
`OpenAPI.server_source` extension seam — loading Servo.jl enables
`framework = :Servo`. `OpenAPI.serverplan` is the staged sibling of
`OpenAPI.plan` and rejects documents whose requests cannot be decoded
faithfully (for example `multipart/mixed` request bodies, or two exploded
object query parameters whose wire names cannot be told apart).

The generated module header lists every handler signature the implementation
must define. Handler functions receive the raw request first, then typed path
parameters in template order, then a required body; optional parameters arrive
as keyword arguments only when the request supplied them.

```julia
include("ExampleServer.jl")

module Handlers

using HTTP

# GET /widgets/{id} -> get_widget(request, id::Int64; verbose = ABSENT)
function get_widget(request, id; verbose = false)
    return lookup_widget(id; verbose)      # encoded, validated, 200
end

# This operation documents 204, so nothing becomes an empty 204 response.
delete_widget(request, id) = nothing

# Return an HTTP.Response directly for custom behavior.
create_widget(request, body) = HTTP.Response(409, "already exists")

end

router = HTTP.Router()
ExampleServer.register!(router, Handlers; path_prefix = "/v1")
server = HTTP.serve!(router, "127.0.0.1", 8080)
```

`register!(router, impl; path_prefix, middleware)` mounts every documented
operation and fails eagerly, listing the expected signatures, when `impl` is
missing any handler. `middleware` wraps each operation handler
(`middleware(handler) -> handler`). `register` is kept as an alias, and the
handler contract — implementation module second, typed positional parameters,
typed-value-or-`HTTP.Response` returns — matches the shape OpenAPI.jl 0.2.x
users generated with `-g julia-server`.

Request decoding mirrors client encoding: parameter styles (`simple`, `label`,
`matrix`, `form`, `spaceDelimited`, `pipeDelimited`, `deepObject`), header and
cookie parameters, JSON, `application/x-www-form-urlencoded`, and
`multipart/form-data` request bodies, with request-direction schema validation
before handlers run. Decoding failures produce structured JSON `400` (or `415`
for undocumented media types) responses without invoking the handler. Response
values are validated against the output-direction schema and encoded from the
first documented success response. Returning `nothing` follows that response:
it emits an empty body when the response has no content, or JSON `null` when
the selected JSON schema accepts null. A full `HTTP.Response` bypasses generated
status, header, and body validation. The handler owns that validation.

Generated server stubs do not authenticate or authorize requests. Apply a
`middleware` that enforces the operation's security policy before it calls the
handler. `serverplan` rejects request-body Encoding Objects that the generated
HTTP server cannot recover faithfully. This includes nested encodings, custom
multipart part headers, and explicit body encoding style modifiers.

## Pipeline and diagnostics

The public stages are separate so applications can inspect or cache them.

- `OpenAPI.load(source)` parses one root document and validates it against the
  official schema for its OAS minor line. It returns an immutable
  `SourceDocument` with source identity, format, version, and source locations.
- `OpenAPI.check(source)` returns structured `Diagnostic` values instead of
  throwing for document validation errors.
- `OpenAPI.normalize(source)` resolves references and creates an immutable,
  version-neutral `NormalizedAPI`.
- `OpenAPI.plan(source; name="ApiClient")` creates deterministic Julia model
  and operation plans.
- `OpenAPI.client(source; ...)` emits source and optionally writes it to a
  file.

Errors use stable diagnostic codes and resource plus JSON Pointer locations.
JSON and YAML mappings reject duplicate keys. Parsers reject alias cycles,
non-finite numbers, excessive nesting, and documents that exceed configured
limits.

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
uses the isolated `OpenAPI.SchemaEngine` module for resource identity, URI
resolution, JSON Pointer, anchors, schema dialects, schema compilation, and
runtime validation.

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

## Generated model behavior

Generated structs are a typed view over the document's JSON Schemas. Runtime
schema validation remains authoritative. This design protects correctness when
a Julia field type cannot express every schema rule.

Implemented model behavior includes:

- objects, arrays, tuples, dictionaries, primitives, enums, and nullable types;
- required, optional, and explicit-null values;
- `allOf`, `oneOf`, `anyOf`, and discriminators;
- recursive models and recursive aliases;
- `additionalProperties`, `patternProperties`, `propertyNames`, and closed
  objects;
- JSON Schema assertions such as `const`, `not`, conditions, dependent rules,
  bounds, formats, and unevaluated constraints through runtime validation;
- `readOnly` and `writeOnly` request and response projections;
- Julia `Date`, `Time`, `DateTime`, `UUID`, and base64 byte values;
- `format: date-time` maps to `Dates.DateTime` by default, decoding RFC 3339
  offsets by normalizing to UTC; generate with `datetime = :zoned` to map to
  `TimeZones.ZonedDateTime` instead, preserving offsets end to end (the
  generated module then depends on TimeZones.jl);
- deterministic names with protection against Julia keywords, Base/Core names,
  and generated runtime names.

An unusual schema can plan to `Any` when no useful Julia type exists. It is
still validated at request and response boundaries. Custom JSON Schema dialects
and custom vocabularies can therefore retain correct validation while using a
less precise Julia type.

Set `validate_requests=false` or `validate_responses=false` on a generated
`Client` only when the application accepts that loss of boundary validation.
For example, a response schema with `additionalProperties: false` rejects a new
server field. This is contract-correct but can make a client less tolerant of
an API that changes outside its published contract. With response validation
disabled, that policy also reaches nested generated models. Unknown response
properties are ignored, and an explicit null on an optional response property
decodes to `nothing` even when the document marks that property non-nullable.
Missing optional properties still decode to `ABSENT`. Values that cannot fit
the generated Julia type can still raise `DecodeError`.

## HTTP behavior

Generated clients support:

- path, query, header, and cookie parameters;
- `simple`, `label`, `matrix`, `form`, `spaceDelimited`, `pipeDelimited`, and
  `deepObject` serialization where the specification permits each style;
- `allowReserved`, `allowEmptyValue`, explode defaults, and parameter `content`;
- JSON and structured-suffix JSON media types;
- text and binary bodies;
- `application/x-www-form-urlencoded` bodies;
- multipart bodies, per-property encodings, documented part headers, uploads,
  and one required level of nested named OAS 3.2 encoding;
- JSON Lines, NDJSON, JSON text sequences, and GeoJSON text sequences when the
  body is described by a normal schema;
- exact, wildcard, and structured-suffix media negotiation;
- exact response codes, `1XX` through `5XX` ranges, and `default` responses;
- documented response headers, including repeated headers and `Set-Cookie`;
- operation, path, and root servers, relative server URLs, named servers, and
  validated server variables;
- request and response validation with input/output JSON Schema semantics.

Use `content_type=...` and `accept=...` on an operation when the document offers
more than one representation. Use `request_headers` for one call and
`Client(headers=...)` for all calls. `request_options` passes options to the
HTTP transport. Streaming calls default to HTTP/1.1 because consumer-driven
stream cancellation closes one request connection. Set `protocol=:auto` or
`:h2` in `request_options` when the caller accepts HTTP/2 stream lifecycle
semantics. Buffered calls keep HTTP.jl's automatic protocol selection.

Responses are decoded by status alone when a server omits its Content-Type
header, or misreports it while only one media type is documented for that
status; `UnexpectedContentType` is thrown only when several documented media
types make the choice ambiguous. A `2XX` status the document does not describe
never fails the call: an empty body returns `nothing` and a payload returns
raw bytes. Undocumented error statuses still throw `ApiError`.

## Streaming responses

Pass `stream_to = Channel(n)` to any operation to consume the response body
incrementally, e.g. long-running watch endpoints or large exports:

```julia
events = Channel{Any}(16)
ExampleClient.watch_pods(; client, stream_to = events)  # returns at the response head
for event in events
    # each item is decoded to the documented response type
end
```

The call returns as soon as the response head arrives (the channel itself, or
an `ApiResponse` whose body is the channel with `with_http_info = true`), and a
background task decodes items onto the channel. `application/json` bodies split
into consecutive JSON documents, each decoded against the documented response
schema — the convention used by Kubernetes-style watch endpoints. JSON Lines
and NDJSON bodies decode each line to the documented array's element type, and
JSON text sequences split on RFC 7464 record separators. `text/*` yields lines
and any other media type yields raw byte chunks. The channel closes when the
response ends, closes with the error when decoding or validation fails, and
closing it from the consumer side aborts the transfer. Error statuses still
throw `ApiError` with the fully buffered error body.

A registered response decoder also applies to streaming calls. The runtime
calls it once for each framed item and puts its return value directly on the
channel. This is an escape hatch for deployed APIs whose streaming wire format
does not match the response schema. Register the full parameterized media type
to limit the override to that stream:

```julia
ExampleClient.codec!(
    client,
    "application/json;stream=watch";
    decode = (bytes, media_type) -> JSON.parse(String(bytes)),
)
```

This decoder does not replace the decoder for plain `application/json`.

For a custom media type, register an encoder or decoder:

```julia
ExampleClient.codec!(
    client,
    "application/cbor";
    encode = (value, media_type) -> encode_cbor(value),
    decode = (bytes, media_type) -> decode_cbor(bytes),
)
```

XML metadata is retained in the schema but does not generate an XML codec.
Register a custom codec for XML or another non-built-in representation.

## Security

Generated clients implement OpenAPI security requirement alternatives and
combinations. Supported credentials include:

- API keys in headers, query parameters, or cookies;
- HTTP Basic and Bearer authentication;
- other HTTP authentication values;
- OAuth 2.0 and OpenID Connect bearer tokens with documented scope checks;
- mutual TLS through HTTP request options.

```julia
ExampleClient.credential!(
    client,
    "bearerAuth",
    ExampleClient.BearerCredential("token"; scopes = ["widgets:read"]),
)
```

`authorization!(client, token)` is a convenience for every bearer-compatible
scheme in a document. The generated client does not acquire or refresh OAuth or
OpenID Connect tokens. The caller owns that lifecycle.

By default, a secured operation fails before network access when no documented
credential alternative can be satisfied. Set `require_credentials=false` only
when an external HTTP layer supplies authentication.

## Support boundary

The loader and normalizer preserve more OpenAPI information than an outgoing
client needs. The following boundaries are intentional and explicit:

| Feature | Status |
| --- | --- |
| OAS 3.0.x, 3.1.x, and 3.2.x document loading | Supported |
| JSON and YAML, with duplicate-key rejection | Supported |
| Local, same-origin, opt-in remote, anchor, and recursive references | Supported |
| Standard operations, OAS 3.2 `QUERY`, and `additionalOperations` | Supported |
| Callback and webhook operations | Normalized and validated; no outgoing client functions are emitted |
| Link Objects | Preserved; no automatic follow-up operation is emitted |
| XML Object mapping | Preserved as schema metadata; use a custom media codec |
| OAS 3.2 `querystring` parameters | **Deferred. Client planning fails with `unsupported_querystring_generation`.** |
| OAS 3.2 streaming `itemSchema`, `itemEncoding`, and `prefixEncoding` | **Deferred. Client planning fails with `unsupported_streaming_generation`.** |

The two deferred features fail during planning. They never produce a client
that silently sends the wrong wire format. Runtime response streaming with
`stream_to` is independent of the deferred OAS 3.2 `itemSchema` generation: it
streams response bodies that are described by normal schemas.

`strict=true` is the default. Use `strict=false` only for documented ecosystem
compatibility cases. Permissive mode can retain ambiguous path templates and a
non-object `deepObject` parameter with warnings. For OAS 3.0 documents, it also
supports the common non-standard `nullable: true` plus `$ref` or `allOf` idiom.
Strict mode follows the normative rule that `nullable` only takes effect when
the same Schema Object defines `type`. Permissive mode does not suppress unsafe
or unsupported behavior.

## Create a document from Julia declarations

The authoring API is intentionally smaller than the ingestion and client
pipeline. It maps common Julia endpoint declarations to an OpenAPI 3.2.0
document.

```julia
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

write("openapi.json", JSON.json(document; pretty = 2))
```

OpenAPI.jl does not depend on a server framework. Framework packages can add
optional `operations` and `register!` methods. Servo.jl provides its OpenAPI
adapter from a downstream package extension.

## Validation evidence

The test suite includes structural schemas published by the OpenAPI Initiative,
adversarial JSON and YAML parsing, external and cyclic references, OAS 3.0/3.1/
3.2 semantics, JSON Schema edge cases, all parameter locations and styles,
security alternatives, server selection, media negotiation, nested multipart
encoding, error responses, and a live local HTTP integration server.

An optional pinned corpus test generates and compiles clients from public
Petstore, Discord, Stripe, and GitHub descriptions. Run it with:

```sh
OPENAPI_CORPUS_TESTS=small julia --project=. -e 'using Pkg; Pkg.test()'
OPENAPI_CORPUS_TESTS=all julia --project=. -e 'using Pkg; Pkg.test()'
OPENAPI_CORPUS_TESTS=all OPENAPI_CORPUS_CASE=GitHub julia --project=. -e 'using Pkg; Pkg.test()'
```

The large Stripe and GitHub descriptions require permissive mode for known
description-level compatibility warnings. Corpus success proves that a client
is generated and compiled. It does not prove that every operation was exercised
against each live service.

Large descriptions also produce large generated modules because the client
keeps the schema data needed for runtime validation. The pinned Stripe and
GitHub cases are scaling gates for this design. Generation is practical, but
loading either client can take tens of seconds. Applications should generate
and precompile these clients during a build step, not at service startup.

## Specification sources

OpenAPI behavior follows the normative
[OpenAPI 3.0.4](https://spec.openapis.org/oas/v3.0.4.html),
[OpenAPI 3.1.1](https://spec.openapis.org/oas/v3.1.1.html), and
[OpenAPI 3.2.0](https://spec.openapis.org/oas/v3.2.0.html) specifications.
The files in `schemas/` are official structural schemas. The normative text
remains authoritative when a published schema differs from it. Their Apache
License 2.0 text is included in [`schemas/LICENSE`](schemas/LICENSE).
