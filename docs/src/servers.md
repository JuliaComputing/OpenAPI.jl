# Generating servers

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
[`OpenAPI.server_source`](@ref) extension seam. An extension must assemble its
generated module through [`OpenAPI.server_module_source`](@ref); this keeps the
runtime data, pasted server code, and generated-code contract guard together.
[`OpenAPI.serverplan`](@ref) is the staged sibling of [`OpenAPI.plan`](@ref)
and rejects documents whose requests cannot be decoded faithfully (for example
`multipart/mixed` request bodies, or two exploded object query parameters
whose wire names cannot be told apart).

## The generated header

The generated module header lists every handler signature the implementation
must define. For a small document:

```@example servergen
using OpenAPI, HTTP

document = """
openapi: 3.1.0
info: {title: Widgets, version: 1.0.0}
paths:
  /widgets/{id}:
    get:
      operationId: getWidget
      parameters:
        - {name: id, in: path, required: true, schema: {type: integer, format: int64}}
        - {name: verbose, in: query, schema: {type: boolean}}
      responses:
        "200":
          description: one widget
          content:
            application/json:
              schema:
                type: object
                required: [id, name]
                properties:
                  id: {type: integer, format: int64}
                  name: {type: string}
    delete:
      operationId: deleteWidget
      parameters:
        - {name: id, in: path, required: true, schema: {type: integer, format: int64}}
      responses:
        "204": {description: deleted}
"""

source_code = OpenAPI.server(document; framework = :HTTP, name = "WidgetsServer")
header = Iterators.takewhile(!startswith("module"), eachsplit(source_code, '\n'))
println(join(header, '\n'))
```

## Implementing handlers

Handler functions receive the raw request first, then typed path parameters in
template order, then a required body; optional parameters arrive as keyword
arguments only when the request supplied them.

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

## Request decoding and response encoding

Request decoding mirrors client encoding: parameter styles (`simple`, `label`,
`matrix`, `form`, `spaceDelimited`, `pipeDelimited`, `deepObject`), header and
cookie parameters, JSON, `application/x-www-form-urlencoded`, and
`multipart/form-data` request bodies, with request-direction schema validation
before handlers run. Decoding failures produce structured JSON `400` (or `415`
for undocumented media types) responses without invoking the handler. Response
values are validated against the output-direction schema and encoded from the
first documented success response. Returning `nothing` follows that response:
it emits an empty body when the response has no content, or JSON `null` when
the selected JSON schema accepts null. A full `HTTP.Response` bypasses
generated status, header, and body validation. The handler owns that
validation.

An operation that documents no success response at all (only error entries)
produces a `missing_success_response` planning warning; its handler's
`nothing` return is answered with an empty `200`, which the OpenAPI
specification permits — response documentation is explicitly non-exhaustive.

## Security and unsupported encodings

Generated server stubs do not authenticate or authorize requests. Apply a
`middleware` that enforces the operation's security policy before it calls the
handler. `serverplan` rejects request-body Encoding Objects that the generated
HTTP server cannot recover faithfully. This includes nested encodings, custom
multipart part headers, and explicit body encoding style modifiers.
