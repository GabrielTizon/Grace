// receive-send-api/src/worker.js

require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const axios       = require('axios');
const { getChannel } = require('./rabbit');

(async () => {
  // 1) Conecta ao RabbitMQ e obtém o channel
  const ch = await getChannel();
  ch.prefetch(10);

  // 2) Garante que a exchange "chat" exista (tipo "topic", durável)
  await ch.assertExchange('chat', 'topic', { durable: true });

  // 3) Agora criamos uma fila NOMEADA e DURÁVEL para o par de IDs (1 → 4):
  //    - Nome da fila:   "channel.1.4"
  //    - Durable: true   (permanece mesmo que o worker pare)
  const queueName = 'channel.1.4';
  await ch.assertQueue(queueName, { durable: true });

  // 4) Vinculamos essa fila à exchange "chat" usando a mesma routing-key:
  //    routing-key = "channel.1.4"
  await ch.bindQueue(queueName, 'chat', queueName);

  console.log(`🟢 rs-worker consumindo fila durável '${queueName}' …`);

  // 5) Começa a consumir mensagens dessa fila nomeada
  ch.consume(queueName, async (msg) => {
    if (!msg) return;

    // 6) Quando chegar uma mensagem, converte JSON → objeto
    const data = JSON.parse(msg.content.toString());

    try {
      // 7) Envia para o Record-API (persistência no Postgres)
      await axios.post('http://record-api:5000/message', data);

      // 8) Se tudo der certo, manda ack para remover da fila
      ch.ack(msg);
      console.log(`✔︎ Gravado: ${data.userIdSend} → ${data.userIdReceive}`);
    } catch (e) {
      // 9) Se falhar, efetua nack para re-enfileirar
      console.error('✖ Record-API error:', e.message);
      ch.nack(msg, false, true);
    }
  });
})();
