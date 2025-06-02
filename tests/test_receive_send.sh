#!/bin/bash

set -e
set -o pipefail

# Configurações
RECEIVE_SEND_API_URL="http://localhost:3000/message" # Endpoint alterado
CONTAINER_NAME="receive-send-api" # Usado para obter JWT_SECRET e gerar JWT
LOG_FILE="receive_send_test.log"

# Detalhes para o payload da mensagem
# userIdSend DEVE ser um usuário que a Auth-API possa validar com o JWT gerado.
# O JWT é gerado para o usuário 'tester'. Certifique-se que 'tester'
# está registrado na Auth-API e que o JWT_SECRET é o mesmo usado pela Auth-API.
USER_ID_SEND="tester" # Usuário que envia (deve corresponder ao usuário no JWT ou ser validável)
USER_ID_RECEIVE="receiverUser" # Usuário que recebe
TEST_MESSAGE="Automated test message from receive-send script"

MESSAGE_PAYLOAD=$(cat <<EOF
{
    "userIdSend": "$USER_ID_SEND",
    "userIdReceive": "$USER_ID_RECEIVE",
    "message": "$TEST_MESSAGE"
}
EOF
)


log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Limpa o arquivo de log no início de uma nova execução de teste
echo "" > "$LOG_FILE"
log_message "Starting Receive-Send-API POST /message test..."

# Pega JWT_SECRET do ambiente do container receive-send-api
# Este JWT_SECRET deve ser o mesmo que a Auth-API usa para validar os tokens
# ou o mesmo que a Auth-API usa para emitir tokens se Receive-Send API os valida localmente (não recomendado).
# O fluxo correto é Receive-Send API chamar Auth-API para validação.
JWT_SECRET_RECEIVE_SEND_API=$(docker exec "$CONTAINER_NAME" printenv JWT_SECRET 2>/dev/null || echo "")

if [ -z "$JWT_SECRET_RECEIVE_SEND_API" ]; then
    log_error "JWT_SECRET não encontrado no container $CONTAINER_NAME. Tentando JWT_SECRET do docker-compose.yml."
    # Fallback para o JWT_SECRET definido no docker-compose.yml para receive-send-api
    JWT_SECRET_RECEIVE_SEND_API="shawarma" # Conforme seu docker-compose.yml
fi

if [ -z "$JWT_SECRET_RECEIVE_SEND_API" ]; then
    log_error "JWT_SECRET não pôde ser determinado para o container $CONTAINER_NAME."
    exit 1
fi
log_message "Usando JWT_SECRET para gerar token de teste."

# Gera JWT dentro do container (para ter acesso ao 'jsonwebtoken' e ao JWT_SECRET correto do container)
log_message "Gerando JWT para o usuário '$USER_ID_SEND' dentro do container $CONTAINER_NAME..."
# O JWT gerado aqui será usado pelo endpoint /message da Receive-Send API,
# que por sua vez o usará para chamar a Auth-API para validação.
JWT=$(docker exec -e JWT_SECRET_ENV="$JWT_SECRET_RECEIVE_SEND_API" "$CONTAINER_NAME" node -e "console.log(require('jsonwebtoken').sign({ user: '$USER_ID_SEND', email: '$USER_ID_SEND@example.com' }, process.env.JWT_SECRET_ENV, { algorithm: 'HS256', expiresIn: '5m' }))")

if [ -z "$JWT" ] || [ "$JWT" == "null" ]; then
    log_error "Falha ao gerar JWT dentro do container."
    exit 1
fi
log_message "JWT gerado com sucesso para o usuário '$USER_ID_SEND'."

log_message "Enviando mensagem para $RECEIVE_SEND_API_URL"
log_message "Payload: $MESSAGE_PAYLOAD"
log_message "Authorization Header: Bearer ${JWT:0:20}..." # Log apenas uma parte do JWT

RESPONSE_BODY_FILE=$(mktemp)
HTTP_STATUS_CODE=$(curl -s -w "%{http_code}" -X POST "$RECEIVE_SEND_API_URL" \
    -H "Authorization: Bearer $JWT" \
    -H "Content-Type: application/json" \
    -d "$MESSAGE_PAYLOAD" \
    -o "$RESPONSE_BODY_FILE" --stderr /dev/null)

RESPONSE_BODY=$(cat "$RESPONSE_BODY_FILE")
rm "$RESPONSE_BODY_FILE"

log_message "Código HTTP recebido: $HTTP_STATUS_CODE"
log_message "Corpo da Resposta: $RESPONSE_BODY"

# Verifica o código de status HTTP (esperando 201 para POST /message bem-sucedido)
if [[ "$HTTP_STATUS_CODE" -ne 201 ]]; then
    log_error "Falha na requisição HTTP para POST /message com código $HTTP_STATUS_CODE."
    log_error "Resposta completa: $RESPONSE_BODY"
    if [[ "$HTTP_STATUS_CODE" -eq 401 ]]; then
         log_error "Recebido 401 Unauthorized. Verifique:"
         log_error "1. Se o usuário '$USER_ID_SEND' existe e está ativo na Auth-API."
         log_error "2. Se o JWT_SECRET usado para gerar este token de teste é o mesmo que a Auth-API usa para validar/decodificar."
         log_error "3. Se a Auth-API (/token com userIdentifier=$USER_ID_SEND) está funcionando e acessível pela Receive-Send-API."
    fi
    exit 1
fi

# Verifica o corpo da resposta (esperando "mesage sended with success")
# A resposta esperada de POST /message é: {"message": "mesage sended with success"}
if echo "$RESPONSE_BODY" | grep -q "mesage sended with success"; then
    log_message "Teste Receive-Send-API (POST /message) concluído com sucesso!"
    exit 0
else
    log_error "Resposta inesperada do POST /message: 'mesage sended with success' não encontrada."
    log_error "Código HTTP: $HTTP_STATUS_CODE (status de sucesso, mas conteúdo inesperado)"
    log_error "Corpo da resposta completa: $RESPONSE_BODY"
    exit 1
fi