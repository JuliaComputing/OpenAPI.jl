# Guidelines For Contributing

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

