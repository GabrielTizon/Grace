const axios = require('axios');
const { getChannel } = require('../rabbit');
const { getUserId } = require('./userResolver');

const AUTH_API_BASE_URL   = process.env.AUTH_API_URL   || 'http://nginx-auth';
const RECORD_API_BASE_URL = process.env.RECORD_API_URL || 'http://record-api:5000';

class MessageService {
  constructor(redisClient) {
    this.redisClient = redisClient;                 // só usado em /worker legado
  }

  /* -------------------------------------------------------------------- */
  /*  TOKEN → Auth-API                                                    */
  /* -------------------------------------------------------------------- */
  async verifyTokenWithAuthAPI(token, userIdentifier) {
    if (!token || !userIdentifier) return false;
    try {
      const { data } = await axios.get(`${AUTH_API_BASE_URL}/token`, {
        headers: { Authorization: `Bearer ${token}` },
        params : { userIdentifier }
      });
      return data?.auth === true;
    } catch (e) {
      console.error('Auth-API verify error:', e.response?.data || e.message);
      return false;
    }
  }

  /* -------------------------------------------------------------------- */
  /*  (não mudou) Helpers GET users, GET messages…                         */
  /* -------------------------------------------------------------------- */

  /* -------------------------------------------------------------------- */
  /*  Enfileirar mensagem (RabbitMQ topic)                                */
  /* -------------------------------------------------------------------- */
  async sendMessageToQueue(userIdSendRaw, userIdReceiveRaw, message, token) {
    // 1. converte e-mail (ou string) → id numérico
    const userIdSend    = await getUserId(userIdSendRaw,    token);   // ex.: 2
    const userIdReceive = await getUserId(userIdReceiveRaw, token);   // ex.: 5

    // 2. prepara payload
    const payload = { userIdSend, userIdReceive, message };

    try {
      // 3. publica na exchange "chat" com routing-key channel.<idSend>.<idReceive>
      const ch = await getChannel();
      await ch.assertExchange('chat', 'topic', { durable: true });
      const routingKey = `channel.${userIdSend}.${userIdReceive}`;
      ch.publish('chat', routingKey, Buffer.from(JSON.stringify(payload)), {
        persistent: true
      });

      console.log(`📤 Enviado para RabbitMQ → ${routingKey}`);
      return { success: true };
    } catch (err) {
      console.error('RabbitMQ publish error:', err);
      return { success: false, error: err.message };
    }
  }

  /* -------------------------------------------------------------------- */
  /*  LEGADO — se ainda quiser usar Redis + endpoint /message/worker       */
  /* -------------------------------------------------------------------- */
  async processMessagesFromQueueToDB(userIdSend, userIdReceive) {
    const queueName = `queue:${userIdSend}_${userIdReceive}`;
    let processed = 0;
    try {
      while (true) {
        const raw = await this.redisClient.rPop(queueName);
        if (!raw) break;
        const msg = JSON.parse(raw);
        const ok  = await axios.post(`${RECORD_API_BASE_URL}/message`, msg);
        if (ok.status === 201) { processed++; }
      }
      return { success: true, message: `Processed ${processed}` };
    } catch (e) {
      return { success: false, error: e.message };
    }
  }
}

module.exports = MessageService;
