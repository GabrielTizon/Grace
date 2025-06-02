#!/bin/bash

# Aborta o script se qualquer comando falhar
set -e
# Garante que o status de saída de um pipeline seja o do último comando que falhou
set -o pipefail

LOG_FILE="deploy.log"

# Limpa o log antigo ou cria um novo
echo "" > "$LOG_FILE"

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_action "Iniciando o processo de deployment..."

# 1. Parar e remover contêineres antigos para um ambiente limpo (opcional, mas recomendado)
log_action "Parando e removendo contêineres existentes (se houver)..."
docker-compose down -v --remove-orphans | tee -a "$LOG_FILE"

# 2. Build das imagens Docker
log_action "Construindo as imagens Docker..."
docker-compose build | tee -a "$LOG_FILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Falha no build das imagens. Verifique o $LOG_FILE."
    exit 1
fi
log_action "Build das imagens concluído com sucesso."

# 3. Iniciar os contêineres em modo detached
log_action "Iniciando os contêineres Docker..."
docker-compose up -d | tee -a "$LOG_FILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Falha ao iniciar os contêineres. Verifique o $LOG_FILE."
    exit 1
fi
log_action "Contêineres iniciados com sucesso."

# 4. Verificações de saúde dos serviços
log_action "Executando verificações de saúde dos serviços..."
# Serviços com healthcheck definido no docker-compose.yml
# nginx-auth reflete a saúde da auth-api através do proxy
services_to_check=("nginx-auth" "record-api" "receive-send-api" "db" "redis")
all_healthy=true

for service in "${services_to_check[@]}"; do
    log_action "Verificando saúde do serviço: $service..."
    healthy_found=false
    for i in {1..30}; do # Tenta por até 60 segundos (30 * 2s)
        status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "$service" 2>/dev/null || echo "error inspecting")
        
        if [ "$status" = "healthy" ]; then
            log_action "Serviço $service está saudável."
            healthy_found=true
            break
        elif [ "$status" = "no healthcheck" ]; then
            log_action "Serviço $service não possui healthcheck definido no docker-compose. Assumindo OK se estiver rodando."
            # Verificar se está rodando
            if [ "$(docker inspect -f '{{.State.Running}}' "$service")" = "true" ]; then
                 log_action "Serviço $service está rodando."
                 healthy_found=true
            else
                log_action "Serviço $service não está rodando."
            fi
            break 
        elif [ "$status" = "error inspecting" ]; then
             log_action "Erro ao inspecionar o serviço $service. Pode ainda não estar pronto."
        fi
        
        if [ $i -eq 30 ]; then
            log_error "Serviço $service não ficou saudável após as tentativas. Status: $status. Verifique os logs do contêiner: docker logs $service"
            all_healthy=false
            # break # Sai do loop de tentativas para este serviço
        fi
        log_action "Serviço $service ainda não está saudável (Status: $status). Tentando novamente em 2 segundos... ($i/30)"
        sleep 2
    done
    if [ "$healthy_found" = false ]; then
        all_healthy=false
    fi
done

if [ "$all_healthy" = false ]; then
    log_error "Um ou mais serviços não ficaram saudáveis. Abortando."
    exit 1
fi
log_action "Todos os serviços verificados estão operacionais."

# 5. Executar testes automatizados
log_action "Executando testes automatizados..."
if [ ! -d "tests" ]; then
    log_error "Diretório 'tests' não encontrado. Os testes não podem ser executados."
    exit 1
fi

cd tests # Navega para o diretório de testes

# Define a ordem de execução dos testes
# test_auth.sh: Gera jwt.txt, necessário para integracao_test.sh
# test_record.sh e test_receive_send.sh: Testes mais isolados de API
# integracao_test.sh: Teste E2E que depende dos outros serviços e do jwt.txt
declare -a test_scripts=(
    "test_auth.sh"
    "test_record.sh"
    "test_receive_send.sh"
    "integracao_test.sh"
)

for test_script in "${test_scripts[@]}"; do
    log_action "Executando script de teste: $test_script..."
    if [ -f "$test_script" ]; then
        chmod +x "$test_script" # Garante que o script é executável
        # Redireciona stdout e stderr do script de teste para o log principal e para o console
        if ./"$test_script" >> "../$LOG_FILE" 2>&1; then
            log_action "Teste $test_script passou."
        else
            log_error "Teste $test_script FALHOU. Verifique o $LOG_FILE para detalhes."
            # Opcional: parar a implantação na primeira falha de teste
            # exit 1
            all_healthy=false # Marca que um teste falhou
        fi
    else
        log_error "Script de teste $test_script não encontrado."
        all_healthy=false
    fi
done

cd .. # Retorna ao diretório original (apis)

if [ "$all_healthy" = false ]; then
    log_error "Um ou mais testes automatizados falharam. Verifique o $LOG_FILE."
    exit 1
fi

log_action "Deployment e testes automatizados concluídos com sucesso!"
exit 0