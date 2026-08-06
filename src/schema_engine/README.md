# Provisional schema engine

This directory contains the generic JSON Schema resource, reference,
compilation, rebasing, and validation code required by OpenAPI.jl and its
generated clients.

The code is intentionally separate from OpenAPI loading, normalization,
planning, and generation. OpenAPI-specific behavior must not enter this
directory.

The implementation came from the experimental JSONSchema.jl
`codex/openapi-foundation` branch. Keeping it here allows the API and behavior
to harden with real OpenAPI documents before a possible future move back to
JSONSchema.jl.
