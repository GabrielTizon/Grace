#!/bin/bash
echo "Testing Record-API..."
response=$(curl -s -X GET http://localhost:5000/messages)
if echo "$response" | grep -q "messages"; then
    echo "Record-API retrieval successful"
else
    echo "Record-API retrieval failed: $response"
    exit 1
fi