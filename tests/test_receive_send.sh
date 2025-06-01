#!/bin/bash
echo "Testing Receive-Send-API..."
if [ ! -f jwt.txt ]; then
    echo "JWT not found. Run test_auth.sh first."
    exit 1
fi
JWT=$(cat jwt.txt)
response=$(curl -s -X POST http://localhost:3000/send -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"message":"test message"}')
if echo "$response" | grep -q "Message sent"; then
    echo "Receive-Send-API successful"
else
    echo "Receive-Send-API failed: $response"
    exit 1
fi