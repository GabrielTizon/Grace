#!/bin/bash

set -e
set -o pipefail

# Configurações
API_URL="http://localhost:3000/send"
CONTAINER_NAME="receive-send-api"
LOG_FILE="receive_send_test.log"
MESSAGE_PAYLOAD='{"message":"test message from automated script"}'

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

echo "" > "$LOG_FILE"
log_message "Starting Receive-Send-API test..."

# Pega JWT_SECRET do ambiente do container
JWT_SECRET=$(docker exec "$CONTAINER_NAME" printenv JWT_SECRET || echo "")

if [ -z "$JWT_SECRET" ]; then
    log_error "JWT_SECRET não encontrado no container $CONTAINER_NAME."
    exit 1
fi
log_message "JWT_SECRET obtido do container."

# Gera JWT dentro do container (evita problema de módulos localmente)
log_message "Gerando JWT dentro do container $CONTAINER_NAME..."
JWT=$(docker exec "$CONTAINER_NAME" node -e "console.log(require('jsonwebtoken').sign({ user: 'tester' }, process.env.JWT_SECRET, { algorithm: 'HS256', expiresIn: '1h' }))")

if [ -z "$JWT" ]; then
    log_error "Falha ao gerar JWT dentro do container."
    exit 1
fi
log_message "JWT gerado com sucesso."

log_message "Enviando mensagem para $API_URL"
log_message "Payload: $MESSAGE_PAYLOAD"

RESPONSE_BODY_FILE=$(mktemp)
HTTP_STATUS_CODE=$(curl -s -w "%{http_code}" -X POST "$API_URL" \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    -d "$MESSAGE_PAYLOAD" \
    -o "$RESPONSE_BODY_FILE" --stderr /dev/null)

RESPONSE_BODY=$(cat "$RESPONSE_BODY_FILE")
rm "$RESPONSE_BODY_FILE"

log_message "Código HTTP recebido: $HTTP_STATUS_CODE"
log_message "Resposta: $RESPONSE_BODY"

if [[ "$HTTP_STATUS_CODE" -lt 200 || "$HTTP_STATUS_CODE" -ge 300 ]]; then
    log_error "Falha na requisição HTTP com código $HTTP_STATUS_CODE."
    log_error "Resposta completa: $RESPONSE_BODY"
    [[ "$HTTP_STATUS_CODE" -eq 401 ]] && log_error "401 Unauthorized. Verifique se o JWT é válido ou expirou."
    [[ "$HTTP_STATUS_CODE" -eq 403 ]] && log_error "403 Forbidden. JWT válido, mas sem permissão para ação."
    exit 1
fi

if echo "$RESPONSE_BODY" | grep -q "Message sent"; then
    log_message "Teste Receive-Send-API concluído com sucesso!"
    exit 0
else
    log_error "Resposta inesperada: 'Message sent' não encontrada."
    log_error "Código HTTP: $HTTP_STATUS_CODE (sucesso, mas conteúdo inesperado)"
    log_error "Resposta completa: $RESPONSE_BODY"
    exit 1
fi
