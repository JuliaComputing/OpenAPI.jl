java -jar openapi-generator-cli.jar generate \
    -i ../../specs/petstore_v3.json \
    -g julia-server \
    -o petstore \
    --additional-properties=packageName=PetStoreServer \
    --additional-properties=exportModels=true
