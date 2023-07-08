java -jar openapi-generator-cli.jar generate \
    -i ../specs/modelgen.json \
    -g julia-client \
    -o ModelGenClient \
    --additional-properties=packageName=ModelGenClient
java -jar openapi-generator-cli.jar generate \
    -i ../specs/modelgen.json \
    -g julia-server \
    -o ModelGenServer \
    --additional-properties=packageName=ModelGenServer
