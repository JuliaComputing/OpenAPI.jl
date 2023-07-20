java -jar openapi-generator-cli.jar generate \
    -i ../specs/forms.json \
    -g julia-client \
    -o FormsClient \
    --additional-properties=packageName=FormsClient
java -jar openapi-generator-cli.jar generate \
    -i ../specs/forms.json \
    -g julia-server \
    -o FormsServer \
    --additional-properties=packageName=FormsServer
