# API reference

OpenAPI.jl does not export names. Every public name below is used through the
`OpenAPI` namespace. Generated modules have their own surface (`Client`,
operation functions, model types, `register!`); that surface is documented by
the generated module itself and in the manual pages.

```@docs
OpenAPI.OpenAPI
```

## Reading and validating documents

```@docs
OpenAPI.load
OpenAPI.check
OpenAPI.read
OpenAPI.parse
OpenAPI.validate
OpenAPI.SourceDocument
OpenAPI.DocumentVersion
OpenAPI.oas_family
```

## Source locations and diagnostics

```@docs
OpenAPI.location
OpenAPI.SourceLocation
OpenAPI.SourcePosition
OpenAPI.Diagnostic
OpenAPI.OpenAPIError
```

## Normalization

```@docs
OpenAPI.normalize
OpenAPI.NormalizedAPI
```

## Planning and code generation

```@docs
OpenAPI.plan
OpenAPI.ClientPlan
OpenAPI.client
OpenAPI.serverplan
OpenAPI.ServerPlan
OpenAPI.server
OpenAPI.server_source
OpenAPI.server_module_source
```

## Document authoring

```@docs
OpenAPI.document
OpenAPI.Operation
OpenAPI.Param
OpenAPI.SchemaRegistry
OpenAPI.schemaof
OpenAPI.obj
```

## Extension seams

```@docs
OpenAPI.register!
OpenAPI.operations
```

## Schema engine

```@docs
OpenAPI.SchemaEngine
OpenAPI.Resources
```

## Generated-code contract

```@docs
OpenAPI.Runtime
OpenAPI.Runtime.CONTRACT_VERSION
OpenAPI.Runtime.require_contract
OpenAPI.Runtime.Spec
```
