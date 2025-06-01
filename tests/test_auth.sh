#!/bin/bash
echo "Testing Auth-API..."
response=$(curl -s -X POST http://localhost:9000/register -H "Content-Type: application/json" -d '{"username":"test","password":"test"}')
if echo "$response" | grep -q "token"; then
    echo "Auth-API register successful"
    echo "$response" | jq -r '.token' > jwt.txt
else
    echo "Auth-API register failed: $response"
    exit 1
fi