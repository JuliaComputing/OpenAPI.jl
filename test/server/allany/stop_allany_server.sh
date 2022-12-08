#!/usr/bin/env bash

echo "stopping allany server"
curl "http://127.0.0.1:8081/stop" >/dev/null 2>&1
echo "stopped allany server"