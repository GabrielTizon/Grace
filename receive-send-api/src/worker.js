// src/worker.js
require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const axios = require('axios');
const { getChannel } = require('./rabbit');

(async () => {
  const ch = await getChannel();
  ch.prefetch(10);

  // cria exchange topic
  await ch.assertExchange('chat', 'topic', { durable: true });

  // fila anônima exclusiva para o worker
  const { queue } = await ch.assertQueue('', { exclusive: true });

  // recebe tudo que começar com channel.<qualquer>.<qualquer>
  await ch.bindQueue(queue, 'chat', 'channel.*.*');

  console.log('🟢 Worker aguardando mensagens…');

  ch.consume(queue, async (msg) => {
    if (!msg) return;
    const data = JSON.parse(msg.content.toString());
    try {
      await axios.post('http://record-api:5000/message', data);
      ch.ack(msg);
      console.log(`✔︎ Gravado: ${data.userIdSend} → ${data.userIdReceive}`);
    } catch (e) {
      console.error('✖ Record-API error:', e.message);
      ch.nack(msg, false, true);          // devolve à fila
    }
  });
})();
