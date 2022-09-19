echo "stopping openapi-petstore server"
docker stop openapi-petstore
docker rm openapi-petstore 2>/dev/null
echo "stopped openapi-petstore server"