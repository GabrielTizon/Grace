#!/bin/bash
set -euo pipefail
TOKEN_API="http://localhost:9003/token"

echo "🔹 Gerando tokens …"
TOK1=$(curl -s -X POST $TOKEN_API -H 'Content-Type: application/json' \
        -d '{"email":"user1@mail.com","password":"senha123"}' | jq -r .token)
TOK2=$(curl -s -X POST $TOKEN_API -H 'Content-Type: application/json' \
        -d '{"email":"user2@mail.com","password":"senha321"}' | jq -r .token)
TOK3=$(curl -s -X POST $TOKEN_API -H 'Content-Type: application/json' \
        -d '{"email":"user3@mail.com","password":"senha123"}' | jq -r .token)
TOK4=$(curl -s -X POST $TOKEN_API -H 'Content-Type: application/json' \
        -d '{"email":"user4@mail.com","password":"senha321"}' | jq -r .token)

curl -H "Authorization: Bearer $TOK1" \
     "localhost:9003/token?userIdentifier=user1@mail.com"

curl -H "Authorization: Bearer $TOK2" \
     "localhost:9003/token?userIdentifier=user1@mail.com"

curl -H "Authorization: Bearer $TOK3" \
     "localhost:9003/token?userIdentifier=user1@mail.com"

curl -H "Authorization: Bearer $TOK4" \
     "localhost:9003/token?userIdentifier=user1@mail.com"


# Exporta para os próximos scripts
echo "export TOK1=$TOK1" >  tokens.env
echo "export TOK2=$TOK2" >> tokens.env
echo "export TOK3=$TOK3" >> tokens.env
echo "export TOK4=$TOK4" >> tokens.env
echo "✓ tokens salvos em tokens.env"
