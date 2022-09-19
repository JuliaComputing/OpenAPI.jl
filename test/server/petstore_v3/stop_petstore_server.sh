#!/usr/bin/env bash

echo "stopping petstore v3 server"
curl "http://127.0.0.1:8081/stop" >/dev/null 2>&1
echo "stopped petstore v3 server"