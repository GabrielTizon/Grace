# Sistema de Microserviços

## Arquitetura

![Diagrama de Arquitetura](architecture.png)

- **Auth-API (PHP)**: Gerencia registro e autenticação (JWT). Lógica em `AuthService`, acesso ao banco via `UserModel`, cache de tokens e usuários no Redis.
- **Record-API (Python)**: Armazena mensagens no Redis (cache) e PostgreSQL (persistência). Lógica em `MessageService`, acesso ao banco via `MessageModel`.
- **Receive-Send-API (Node.js)**: Envia e recebe mensagens via Redis (cache). Lógica em `MessageService`.
- **Redis**: Cache para tokens, usuários, e mensagens (expiração de 1 hora).
- **PostgreSQL**: Banco relacional com volume persistente (`db-data`).
- **Rede**: `app-network` (bridge) para comunicação entre containers.
- **Volumes**: Persistência para PostgreSQL (`db-data`).

## Comandos de Build

```bash
docker-compose build