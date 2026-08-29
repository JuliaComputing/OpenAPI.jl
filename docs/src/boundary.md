# Support boundary

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
| Swagger/OAS 2.0 input | **Not supported. Convert to OpenAPI 3.x first (see [the migration guide](migration.md)).** |
| OAS 3.2 `querystring` parameters | **Deferred. Client planning fails with `unsupported_querystring_generation`.** |
| OAS 3.2 streaming `itemSchema`, `itemEncoding`, and `prefixEncoding` | **Deferred. Client planning fails with `unsupported_streaming_generation`.** |

The two deferred features fail during planning. They never produce a client
that silently sends the wrong wire format. Runtime response streaming with
`stream_to` is independent of the deferred OAS 3.2 `itemSchema` generation: it
streams response bodies that are described by normal schemas.

## Strict and permissive mode

`strict=true` is the default. Use `strict=false` only for documented ecosystem
compatibility cases. Permissive mode can retain ambiguous path templates, a
non-object `deepObject` parameter, and operation security naming schemes the
document never declares (see [Security](security.md)), each with warnings. For
OAS 3.0 documents, it also supports the common non-standard `nullable: true`
plus `$ref` or `allOf` idiom. Strict mode follows the normative rule that
`nullable` only takes effect when the same Schema Object defines `type`.
Permissive mode does not suppress unsafe or unsupported behavior.

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
