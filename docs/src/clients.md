# Generating clients

[`OpenAPI.client`](@ref) reads an OpenAPI 3.0, 3.1, or 3.2 document and emits
one deterministic Julia module. Load `HTTP` before reading a URL; local files
and inline JSON or YAML do not need `HTTP` during generation.

```julia
using OpenAPI, HTTP

OpenAPI.client(
    "https://example.com/openapi.yaml";
    name = "ExampleClient",
    path = "ExampleClient.jl",
)
```

The long form runs the same pipeline in stages, which lets an application
inspect or cache the intermediate values (see
[Pipeline and diagnostics](pipeline.md)):

```julia
source = OpenAPI.load("https://example.com/openapi.yaml")
api = OpenAPI.normalize(source)
plan = OpenAPI.plan(api; name = "ExampleClient")
OpenAPI.client(plan; path = "ExampleClient.jl")
```

The generated file imports `OpenAPI`, `HTTP`, and `JSON`. It also imports the
Julia standard libraries `Base64`, `Dates`, and `UUIDs`. Add the three package
dependencies to the environment that will include the generated file.

## Calling operations

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

## Responses and errors

Pass `with_http_info=true` to receive an `ApiResponse` with the status, raw
headers, decoded documented headers, and typed body. A non-2xx response throws
`ApiError`. The error keeps the raw body even when documented error decoding
fails.

Responses are decoded by status alone when a server omits its Content-Type
header, or misreports it while only one media type is documented for that
status; `UnexpectedContentType` is thrown only when several documented media
types make the choice ambiguous. A `2XX` status the document does not describe
never fails the call: an empty body returns `nothing` and a payload returns
raw bytes. Undocumented error statuses still throw `ApiError`.

## Request options and content negotiation

Use `content_type=...` and `accept=...` on an operation when the document
offers more than one representation. Use `request_headers` for one call and
`Client(headers=...)` for all calls. `request_options` passes options to the
HTTP transport. Streaming calls default to HTTP/1.1 because consumer-driven
stream cancellation closes one request connection. Set `protocol=:auto` or
`:h2` in `request_options` when the caller accepts HTTP/2 stream lifecycle
semantics. Buffered calls keep HTTP.jl's automatic protocol selection.

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

## Date and time mapping

`format: date-time` maps to `Dates.DateTime` by default, decoding RFC 3339
offsets by normalizing to UTC. Generate with `datetime = :zoned` to map to
`TimeZones.ZonedDateTime` instead, preserving offsets end to end; the
generated module then depends on TimeZones.jl.

## Source privacy

Generated schema graphs use content-derived resource identifiers. Local paths,
source URL userinfo, and source URL query strings are not embedded in
generated files. A relative Server Object still depends on the public scheme,
host, and path of the source URL because that location is part of the OpenAPI
resolution rule.
