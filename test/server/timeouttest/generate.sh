java -jar openapi-generator-cli.jar generate \
    -i ../../specs/timeouttest.yaml \
    -g julia-server \
    -o TimeoutTestServer \
    --additional-properties=packageName=TimeoutTestServer
