java -jar openapi-generator-cli.jar generate \
    -i ../../specs/openapigenerator_petstore_v3.json \
    -g julia-server \
    -o petstore \
    --additional-properties=packageName=OpenAPIGenPetStoreServer \
    --additional-properties=exportModels=true
