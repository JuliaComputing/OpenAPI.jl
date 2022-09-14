docker stop openapi-petstore 2> /dev/null
docker rm openapi-petstore 2> /dev/null
docker run --rm -d --name openapi-petstore -e OPENAPI_BASE_PATH=/v3 -e DISABLE_API_KEY=1 -e DISABLE_OAUTH=1 -p 8081:8080 openapitools/openapi-petstore
