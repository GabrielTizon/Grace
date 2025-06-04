# receive-send-api/Dockerfile
FROM node:20-alpine

RUN apt-get update && \
    apt-get install -y gcc libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 1. dependências
COPY package*.json ./
RUN npm install

# 2. código-fonte
COPY src/ ./src

EXPOSE 3000

CMD ["node", "src/index.js"]
