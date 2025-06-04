# receive-send-api/Dockerfile
FROM node:20-alpine

WORKDIR /app

# 0. instala curl (e qualquer utilitário que quiser)
RUN apk add --no-cache curl

# 1. dependências
COPY package*.json ./
RUN npm install          # ou npm ci --omit=dev

# 2. código-fonte
COPY src/ ./src

EXPOSE 3000
CMD ["node", "src/index.js"]
