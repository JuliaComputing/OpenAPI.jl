java -jar openapi-generator-cli.jar generate \
    -i swagger.json \
    -g julia-server \
    -o petstore \
    --additional-properties=packageName=PetStoreServer \
    --additional-properties=exportModels=true
