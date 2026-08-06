# OpenAPI.jl maintainer guide

## Purpose

OpenAPI.jl has two related surfaces:

1. It reads OpenAPI 3.0, 3.1, and 3.2 descriptions and generates typed Julia
   clients.
2. It creates a smaller OpenAPI 3.2 document from declared Julia operations.

The client generator must fail before code emission when it cannot preserve the
specified wire behavior. Do not generate a plausible but incorrect client.

## Architecture

The client pipeline has strict stage boundaries:

```text
source
  -> load and structural validation
  -> reference resolution and normalization
  -> typed client planning
  -> deterministic Julia source generation
  -> generated runtime validation and HTTP transport
```

The main files are:

- `src/loading.jl`: JSON/YAML parsing, official OAS schema checks, source
  identity, limits, and source locations.
- `src/schema_engine/`: provisional generic JSON Schema resources, references,
  dialects, compilation, rebasing, and validation. Keep this directory free of
  OpenAPI-specific behavior so it can move upstream later.
- `src/references.jl`: bounded OpenAPI object reference resolution and the
  adapter to the internal schema engine.
- `src/normalize.jl`: immutable, version-neutral OpenAPI intermediate forms and
  semantic checks.
- `src/planning.jl`: Julia names, model shapes, operation signatures, and
  explicit generation support checks.
- `src/client.jl`: source emission and the runtime embedded in generated
  clients.
- `src/schemas.jl`, `src/document.jl`: Julia type schema mapping and the smaller
  document-authoring API.
- `ext/OpenAPIHTTPExt.jl`: HTTP document retrieval.

## Design rules

- Keep the package export surface empty. Users call `OpenAPI.load`,
  `OpenAPI.normalize`, `OpenAPI.plan`, and `OpenAPI.client` through the module.
- Keep parsed and normalized documents immutable. Do not mutate caller-owned
  input.
- Keep diagnostics stable and machine-readable. Include a resource and JSON
  Pointer location.
- Keep network and file reference access bounded. Preserve same-origin and
  explicit-root defaults.
- Keep generic URI, resource, pointer, reference, dialect, compilation, and
  validation behavior in `src/schema_engine`. Add OpenAPI-specific rules only
  outside that directory.
- Treat `src/schema_engine` as provisional. Preserve its extraction boundary
  so the code can move to JSONSchema.jl after it hardens.
- Do not add a dependency on Servo or another server framework. Downstream
  packages own router integration through package extensions.
- Put generic strict JSON parsing behavior in JSON.jl when it belongs there.
- Treat the normative OpenAPI text as authoritative over published structural
  schemas.
- Preserve distinct missing, explicit-null, request, and response model
  semantics.
- Keep generation deterministic. Sort unordered document maps before they
  affect names or emitted source.
- Do not silently approximate unsupported wire behavior. The known deliberate
  planning failures are OAS 3.2 `querystring` parameters and streaming or
  positional `itemSchema`, `itemEncoding`, and `prefixEncoding` behavior.

## Public types and functions

- `SourceDocument`, `Diagnostic`, `OpenAPIError`: loading and diagnostics.
- `NormalizedAPI`: immutable normalized document.
- `ClientPlan`: deterministic generation plan.
- `load`, `check`, `normalize`, `plan`, `client`: client pipeline.
- `Param`, `Operation`, `document`: declaration-based authoring API.
- `register!`, `operations`: extension seams implemented by downstream server
  packages.

Generated modules have their own public runtime types. Important types include
`Client`, credential types, `Upload`, `MultipartPartHeaders`, `ApiResponse`,
`ApiError`, `SchemaValidationError`, `Absent`, and `ABSENT`.

## Tests

Run the package tests on both supported Julia minor lines:

```sh
julia +1.12 --project=. -e 'using Pkg; Pkg.test()'
julia +1.11 --project=. -e 'using Pkg; Pkg.test()'
```

The focused files separate concerns:

- `test/normalization.jl`: loading, versions, immutability, generated source.
- `test/references.jl`: external, anchor, recursive, and cyclic references.
- `test/semantics.jl`: OpenAPI semantic rules and explicit deferrals.
- `test/models.jl`, `test/discriminators.jl`: schema-to-type edge cases.
- `test/runtime.jl`: generated runtime units.
- `test/runtime_integration.jl`: live local HTTP behavior.
- `test/schema_engine/`: direct resource, compilation, validation, and rebasing
  coverage for the provisional schema engine.
- `test/corpus.jl`: pinned public API descriptions.

Run corpus checks separately:

```sh
OPENAPI_CORPUS_TESTS=small julia --project=. -e 'using Pkg; Pkg.test()'
OPENAPI_CORPUS_TESTS=all julia --project=. -e 'using Pkg; Pkg.test()'
```

When a test changes expected wire bytes, inspect the bytes or HTTP request. A
source-compilation check alone is not enough.

## Dependency development

OpenAPI.jl requires JSON.jl 1.7. The additional schema engine is currently
internal. Changes to it need direct tests and full OpenAPI corpus validation.
Do not couple its internals to OpenAPI normalization or planning.

## Common change workflow

1. Add or pin a specification example that demonstrates the behavior.
2. Add a normalized semantic test before changing generated source.
3. Add runtime or live HTTP coverage when bytes, headers, security, or response
   selection change.
4. Run focused tests.
5. Run the full Julia 1.12 and 1.11 suites.
6. Run the small corpus. Run the full corpus for reference, planning, naming,
   schema, or generation changes.
7. Check `git diff --check` and inspect generated source for deterministic
   output.

Do not push or publish without direct user approval.
