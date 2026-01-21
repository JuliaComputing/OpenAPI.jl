java -jar openapi-generator-cli.jar generate \
    -i ../specs/stresstest.yaml \
    -g julia-client \
    -o StressTestClient \
    --additional-properties=packageName=StressTestClient
