# receive-send-api/Dockerfile
FROM node:20-alpine

WORKDIR /app

# 1. dependências
COPY package*.json ./
RUN npm install

# 2. código-fonte
COPY src/ ./src

EXPOSE 3000

CMD ["node", "src/index.js"]
