java -jar openapi-generator-cli.jar generate \
    -i ../../specs/petstore_v2.json \
    -g julia-client \
    -o petstore \
    --additional-properties=packageName=PetStoreClient \
    --additional-properties=exportModels=true \
    --additional-properties=exportOperations=true
