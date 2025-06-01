FROM node:20.17

WORKDIR /app
COPY src/ .
COPY package.json .

RUN npm install

EXPOSE 3000
CMD ["node", "index.js"]