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

  // 3) Busca TODOS os usuários na Auth-API:
  //    • Espera que Auth-API tenha rota GET /user?all=true retornando array de usuários
  //    • Cada usuário deve ter a propriedade 'id' (número)
  const AUTH_API_BASE_URL = process.env.AUTH_API_URL || 'http://nginx-auth';
  let users = [];
  try {
    const resp = await axios.get(`${AUTH_API_BASE_URL}/user?all=true`);
    users = resp.data;
  } catch (err) {
    console.error('✖ Falha ao buscar usuários da Auth-API:', err.response?.data || err.message);
    process.exit(1);
  }

  // 4) Extrai apenas os IDs e ordena (para gerar pares únicos)
  const ids = users
    .map(u => Number(u.id))
    .filter(n => Number.isInteger(n))
    .sort((a, b) => a - b);

  // 5) Gera todas as combinações não-ordenadas de pares de IDs (i < j)
  const channelPairs = [];
  for (let i = 0; i < ids.length; i++) {
    for (let j = i + 1; j < ids.length; j++) {
      channelPairs.push([ids[i], ids[j]]);
    }
  }

  if (channelPairs.length === 0) {
    console.warn('⚠️ Não há pares de usuários para criar filas. Verifique se há pelo menos 2 usuários cadastrados.');
    process.exit(0);
  }

  // 6) Para cada par (id1, id2): cria fila nomeada "channel.id1.id2", bind e consume
  for (const [id1, id2] of channelPairs) {
    const queueName = `channel.${id1}.${id2}`;

    // 6.1) Declara a fila nomeada e durável
    await ch.assertQueue(queueName, { durable: true });

    // 6.2) Vincula essa fila à exchange "chat" com a mesma routing-key
    //      ou seja, mensagens publicadas com routing-key="channel.id1.id2" irão para esta fila
    await ch.bindQueue(queueName, 'chat', queueName);

    console.log(`🟢 rs-worker preparado para consumir fila durável '${queueName}'`);
    
    // 6.3) Começa a consumir mensagens dessa fila nomeada
    ch.consume(queueName, async (msg) => {
      if (!msg) return;
      const data = JSON.parse(msg.content.toString());

      try {
        // 6.4) Grava no Record-API (Postgres) via HTTP
        await axios.post('http://record-api:5000/message', data);

        // 6.5) Se OK, manda ACK para remover da fila
        ch.ack(msg);
        console.log(`✔︎ Gravado: ${data.userIdSend} → ${data.userIdReceive} [via '${queueName}']`);
      } catch (e) {
        // 6.6) Se falhar, manda NACK para re-enfileirar
        console.error(`✖ Record-API error ao processar mensagem de ${data.userIdSend} para ${data.userIdReceive}:`, e.message);
        ch.nack(msg, false, true);
      }
    });
  }

  // 7) Pronto: o worker está consumindo todas as filas "channel.id1.id2"
  console.log('🚀 rs-worker rodando e aguardando mensagens em todas as filas de canal…');
})();
