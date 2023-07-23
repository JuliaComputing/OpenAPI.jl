java -jar openapi-generator-cli.jar generate \
    -i ../../specs/openapigenerator_petstore_v3.json \
    -g julia-client \
    -o petstore \
    --additional-properties=packageName=OpenAPIGenPetStoreClient \
    --additional-properties=exportModels=true \
    --additional-properties=exportOperations=true
