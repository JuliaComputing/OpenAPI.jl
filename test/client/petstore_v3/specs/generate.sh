java -jar openapi-generator-cli.jar generate \
    -i openapi.json \
    -g julia-client \
    -o petstore \
    --additional-properties=packageName=PetStoreClient \
    --additional-properties=exportModels=true \
    --additional-properties=exportOperations=true
