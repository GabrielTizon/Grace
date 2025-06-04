require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const axios = require('axios');
const { getChannel } = require('./rabbit');

(async () => {
  const ch = await getChannel();
  ch.prefetch(10);                              // carrega 10 por vez

  // Consumir *todas* as filas do padrão channel.*
  const queues = await ch.assertQueue('', { exclusive: true });
  await ch.bindQueue(queues.queue, 'amq.rabbitmq.log', 'channel.*'); // workaround para não criar exchange extra

  const consumeQueue = async (queue) => {
    await ch.assertQueue(queue, { durable: true });
    ch.consume(queue, async (msg) => {
      if (!msg) return;
      const data = JSON.parse(msg.content.toString());
      try {
        await axios.post('http://record-api:5000/message', data);
        ch.ack(msg);
      } catch (e) {
        console.error('Erro gravando em Record-API:', e.message);
        ch.nack(msg, false, true);              // requeue
      }
    });
  };

  // Descobre quais filas existem no broker e começa a consumir
  const res = await ch.checkQueue('channel.1.4').catch(() => null);
  // Para demo: consuma as filas conforme necessário
  await consumeQueue('channel.1.4');
})();
