#!/bin/bash
echo "Subindo todos os serviços..."
docker-compose up -d

echo "Aguardando serviços subirem..."
sleep 10

echo "Testando saúde dos serviços:"
curl -s http://localhost:8081/health && echo " Auth-API OK"
curl -s http://localhost:5000/health && echo " Record-API OK"
curl -s http://localhost:3000/health && echo " Receive-Send-API OK"
