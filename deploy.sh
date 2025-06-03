#!/usr/bin/env bash
# -------------------------------------------------
# deploy.sh  –  build, up, health-check + logging
# -------------------------------------------------
set -e          # aborta se qualquer comando falhar

LOG_FILE="deploy.log"
exec > >(tee -a "$LOG_FILE") 2>&1   # tudo vai p/ console + log

echo "=== $(date '+%F %T')  DEPLOY INICIADO ==="

# 1. Build e start
docker compose pull          # opcional: obtém imagens já existentes
docker compose build
docker compose up -d         # inicia em modo detached

# 2. Health-check simples (até 60 s) para serviços chave
SERVICES=(db redis record-api receive-send-api nginx-auth)
MAX_TRIES=30
SLEEP=10

for service in "${services_to_check[@]}"; do
  echo "Verificando saúde do serviço: $service..."
  for ((i=1; i<=30; i++)); do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$service" 2>/dev/null || true)

    # se não houver healthcheck, verificar se está rodando
    if [[ -z "$status" ]]; then
      running=$(docker inspect -f '{{.State.Running}}' "$service")
      [[ "$running" == "true" ]] && status="running"
    fi

    if [[ "$status" == "healthy" || "$status" == "running" ]]; then
      echo "→ $service OK"
      break
    fi

    if (( i == 30 )); then
      echo "‼ $service não ficou saudável (status=$status)"
      exit 1
    fi
    sleep 2
  done
done


echo "Todos os serviços estão prontos."

# 3. (Opcional) – pequenos testes de fumaça
curl -fs http://localhost:5000/ >/dev/null
curl -fs http://localhost:3000/ >/dev/null
echo "Smoke-tests básicos passaram."

echo "=== DEPLOY CONCLUÍDO COM SUCESSO ==="
