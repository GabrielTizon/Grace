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

for svc in "${SERVICES[@]}"; do
  echo "Aguardando $svc ficar saudável…"
  for ((i=1; i<=MAX_TRIES; i++)); do
    status=$(docker inspect -f '{{.State.Health.Status 2>/dev/null}}' "$svc" || true)

    # se o serviço não tem healthcheck, só verifica se está rodando
    [[ -z "$status" ]] && status=$(docker inspect -f '{{.State.Running}}' "$svc")

    if [[ "$status" == "healthy" || "$status" == "true" ]]; then
      echo "→ $svc OK"
      break
    fi

    if (( i == MAX_TRIES )); then
      echo "‼ $svc não ficou saudável (status=$status). Veja docker logs $svc" >&2
      exit 1
    fi
    sleep "$SLEEP"
  done
done

echo "Todos os serviços estão prontos."

# 3. (Opcional) – pequenos testes de fumaça
curl -fs http://localhost:5000/ >/dev/null
curl -fs http://localhost:3000/ >/dev/null
echo "Smoke-tests básicos passaram."

echo "=== DEPLOY CONCLUÍDO COM SUCESSO ==="
