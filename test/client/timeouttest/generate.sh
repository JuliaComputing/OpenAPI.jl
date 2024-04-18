java -jar openapi-generator-cli.jar generate \
    -i ../../specs/timeouttest.yaml \
    -g julia-client \
    -o TimeoutTestClient \
    --additional-properties=packageName=TimeoutTestClient
