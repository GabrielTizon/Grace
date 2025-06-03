#!/usr/bin/env bash
# --------------------------------------------------------------
#  deploy.sh  –  build, up, health-check e testes automatizados
# --------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_FILE="$SCRIPT_DIR/deploy.log"

# -----------------------------------------------------------------------------
# 1. Logging helpers
# -----------------------------------------------------------------------------
exec > >(tee -a "$LOG_FILE") 2>&1   # tudo que sai vai para console + log

log()   { echo "$(date '+%F %T')  $*"; }
error() { log "ERROR: $*"; exit 1; }

log "=== DEPLOY INICIADO ==="
log "Log completo em: $LOG_FILE"

# -----------------------------------------------------------------------------
# 2. Ambiente limpo
# -----------------------------------------------------------------------------
log "Derrubando contêineres antigos..."
docker compose down -v --remove-orphans

# -----------------------------------------------------------------------------
# 3. Build das imagens
# -----------------------------------------------------------------------------
log "Construindo imagens..."
docker compose build

# -----------------------------------------------------------------------------
# 4. Subir serviços
# -----------------------------------------------------------------------------
log "Subindo stack em modo detached..."
docker compose up -d

# -----------------------------------------------------------------------------
# 5. Health-check (até 60 s)
# -----------------------------------------------------------------------------
SERVICES=("nginx-auth" "record-api" "receive-send-api" "db" "redis")
MAX_TRIES=30
SLEEP_SEC=2

for svc in "${SERVICES[@]}"; do
  log "→ Aguardando saúde do serviço: $svc"
  for ((i=1; i<=MAX_TRIES; i++)); do
    # status = healthy | unhealthy | starting | '' (sem healthcheck)
    status=$(docker inspect -f '{{.State.Health.Status 2>/dev/null}}' "$svc" || true)

    if [[ "$status" == "healthy" ]]; then
      log "   $svc saudável ✔︎"
      break
    elif [[ -z "$status" ]]; then
      # sem healthcheck → checar se container está RUNNING
      running=$(docker inspect -f '{{.State.Running}}' "$svc")
      [[ "$running" == "true" ]] && { log "   $svc rodando (sem healthcheck) ✔︎"; break; }
    fi

    if (( i == MAX_TRIES )); then
      error "$svc não ficou saudável após $((MAX_TRIES*SLEEP_SEC)) s (estado: ${status:-no healthcheck})"
    fi
    sleep "$SLEEP_SEC"
  done
done

log "Todos os serviços OK."

# -----------------------------------------------------------------------------
# 6. Executar testes
# -----------------------------------------------------------------------------
TEST_DIR="$SCRIPT_DIR/tests"
[[ -d "$TEST_DIR" ]] || error "Diretório de testes não encontrado: $TEST_DIR"

declare -a TESTS=(
  "test_auth.sh"
  "test_record.sh"
  "test_receive_send.sh"
  "integracao_test.sh"
)

for t in "${TESTS[@]}"; do
  [[ -x "$TEST_DIR/$t" ]] || error "Script de teste não encontrado ou sem permissão: $t"
  log "→ Rodando $t ..."
  (cd "$TEST_DIR" && "./$t")
  log "   $t passou ✔︎"
done

log "=== DEPLOY E TESTES FINALIZADOS COM SUCESSO ==="
