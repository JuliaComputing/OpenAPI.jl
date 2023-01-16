java -jar openapi-generator-cli.jar generate \
    -i ../../specs/allany.yaml \
    -g julia-client \
    -o AllAnyClient \
    --additional-properties=packageName=AllAnyClient
