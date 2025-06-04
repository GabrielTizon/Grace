#!/bin/bash
set -euo pipefail

echo "🔹 Criando usuários na Auth-API …"

API="http://localhost:9003/user"
curl -s -o /dev/null -w "\n✓ user1\n" -X POST $API -H 'Content-Type: application/json' \
  -d '{"name":"Usuário 1","lastName":"Silva","email":"user1@mail.com","password":"senha123"}'
curl -s -o /dev/null -w "✓ user2\n" -X POST $API -H 'Content-Type: application/json' \
  -d '{"name":"Usuário 2","lastName":"Souza","email":"user2@mail.com","password":"senha321"}'
curl -s -o /dev/null -w "✓ user3\n" -X POST $API -H 'Content-Type: application/json' \
  -d '{"name":"Usuário 3","lastName":"Oliveira","email":"user3@mail.com","password":"senha123"}'
curl -s -o /dev/null -w "✓ user4\n\n" -X POST $API -H 'Content-Type: application/json' \
  -d '{"name":"Usuário 4","lastName":"Costa","email":"user4@mail.com","password":"senha321"}'
