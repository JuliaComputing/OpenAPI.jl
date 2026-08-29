# Generated modules and the runtime contract

A generated module targets an OpenAPI.jl generated-code contract version. It
also records the exact OpenAPI.jl version that produced it. The module imports
internal `OpenAPI.Runtime` machinery and bakes runtime data shapes — operation
tables, `Runtime.Spec` keywords, schema descriptors, and dialect references —
directly into its source. The result is one generated source artifact, but it
still needs a compatible OpenAPI.jl runtime. Treat it as a build product, not
as version-independent user code.

Every generated module therefore records and checks its provenance:

- the first line stamps the OpenAPI.jl version that produced the file, and
- before it imports private runtime names, the module calls
  [`OpenAPI.Runtime.require_contract`](@ref)`(N, version)` at load time, where
  `N` is the generated-code contract version
  ([`OpenAPI.Runtime.CONTRACT_VERSION`](@ref)) current at generation time.

A release that changes any part of the generated-code contract bumps
`CONTRACT_VERSION`, so a previously generated module fails at load time with
an error naming the release that generated it and asking for regeneration —
instead of failing mysteriously, or worse silently, inside the runtime.
Releases with the same contract version remain load-compatible, so compatible
runtime fixes do not require regeneration.

## When to regenerate

Regenerate when the guard reports a contract mismatch, or when you want a fix
that changes generated source. Rerun [`OpenAPI.client`](@ref) or
[`OpenAPI.server`](@ref) against your document and commit the new file.

Because generation is deterministic, regenerating from an unchanged document
with the same OpenAPI.jl version reproduces the same file, so a generated
module diffs cleanly in version control.

## Large documents

Large descriptions produce large generated modules because the client keeps
the schema data needed for runtime validation. Generation is practical even
for the biggest public API descriptions (the package's corpus tests pin
Stripe and GitHub), but loading such a client can take tens of seconds.
Applications should generate and precompile these clients during a build step,
not at service startup.
