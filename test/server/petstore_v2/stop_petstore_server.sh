#!/usr/bin/env bash

echo "stopping petstore v2 server"
curl "http://127.0.0.1:8080/stop" >/dev/null 2>&1
echo "stopped petstore v2 server"