#!/bin/bash
set -euo pipefail
source ./tokens.env

echo "🔹 Histórico (Record-API) canal 2 / 5"
curl -s http://localhost:5000/messages_for_channel/1/4 | jq

echo -e "\n🔹 Inbox user4@mail.com via Receive-Send-API"
curl -s "http://localhost:3000/message?user=user4@mail.com" \
     -H "Authorization: Bearer $TOK4" | jq
