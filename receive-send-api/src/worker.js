require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const axios = require('axios');
const { getChannel } = require('./rabbit');

(async () => {
  const ch = await getChannel();
  await ch.assertExchange('chat', 'topic', { durable: true });

  // cria fila exclusiva e liga em channel.*.*
  const { queue } = await ch.assertQueue('', { exclusive: true });
  await ch.bindQueue(queue, 'chat', 'channel.*.*');

  console.log('🟢 rs-worker consumindo exchange chat → channel.*.*');

  ch.prefetch(10);
  ch.consume(queue, async (msg) => {
    if (!msg) return;
    const data = JSON.parse(msg.content.toString());
    try {
      await axios.post('http://record-api:5000/message', data);
      ch.ack(msg);
      console.log(`✔︎ Gravado: ${data.userIdSend} → ${data.userIdReceive}`);
    } catch (e) {
      console.error('✖ Record-API error:', e.message);
      ch.nack(msg, false, true);   // requeue
    }
  });
})();
