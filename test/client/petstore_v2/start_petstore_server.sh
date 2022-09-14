docker stop swagger-petstore 2> /dev/null
docker rm swagger-petstore 2> /dev/null
docker run --rm -d --name swagger-petstore -e SWAGGER_HOST=http://127.0.0.1 -e SWAGGER_BASE_PATH=/v2 -p 8080:8080 swaggerapi/petstore:latest