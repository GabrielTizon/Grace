require('dotenv').config({ path: require('path').resolve(__dirname, '../.env') });
const axios = require('axios');
const { getChannel } = require('./rabbit');

(async () => {
  const ch = await getChannel();
  ch.prefetch(10);

  // Lista de filas que você quer consumir; para demo coloque as que existem
  const channels = ['channel.1.4', 'channel.4.3', 'channel.2.1'];

  for (const queue of channels) {
    await ch.assertQueue(queue, { durable: true });
    ch.consume(queue, async (msg) => {
      if (!msg) return;
      const data = JSON.parse(msg.content.toString());
      try {
        await axios.post('http://record-api:5000/message', data);
        ch.ack(msg);
      } catch (err) {
        console.error('Erro ao gravar:', err.message);
        ch.nack(msg, false, true);          // devolve à fila
      }
    });
    console.log(`Consumindo ${queue}`);
  }
})();