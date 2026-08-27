# Guidelines For Contributing

### Branches

- `release-0.2` (this branch): maintenance line for the OpenAPI.jl 0.2.x series, the runtime for code produced by openapi-generator's `julia-client`/`julia-server` targets. PRs fixing 0.2.x behavior target this branch, and 0.2.x patch releases are registered and tagged from it.
- `main`: OpenAPI.jl 1.x, the pure-Julia generator. It does not include the 0.2.x runtime API (`OpenAPI.Clients`, `OpenAPI.Servers`); changes there do not need openapi-generator updates.

### Updating the code generator

The ["openapi-generator"](https://github.com/OpenAPITools/openapi-generator/) repository contains the code generator for Julia. For any changes that also need updates to the generated code, a PR needs to be made to the `openapi-generator` repo. Relevant files:
- <https://github.com/OpenAPITools/openapi-generator/blob/master/.github/workflows/samples-julia.yaml>
- <https://github.com/OpenAPITools/openapi-generator/tree/master/bin/configs/julia-client-petstore-new.yaml>
- <https://github.com/OpenAPITools/openapi-generator/tree/master/bin/configs/julia-server-petstore-new.yaml>
- <https://github.com/OpenAPITools/openapi-generator/tree/master/samples/client/petstore/julia>
- <https://github.com/OpenAPITools/openapi-generator/tree/master/samples/server/petstore/julia>
- <https://github.com/OpenAPITools/openapi-generator/blob/master/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractJuliaCodegen.java>
- <https://github.com/OpenAPITools/openapi-generator/blob/master/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/JuliaServerCodegen.java>
- <https://github.com/OpenAPITools/openapi-generator/blob/master/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/JuliaClientCodegen.java>
- <https://github.com/OpenAPITools/openapi-generator/tree/master/modules/openapi-generator/src/main/resources/julia-client>
- <https://github.com/OpenAPITools/openapi-generator/tree/master/modules/openapi-generator/src/main/resources/julia-server>

