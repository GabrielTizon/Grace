/* ---------------------------------------------------------------
   MessageService  –  Receive-Send-API
   • Verifica JWT na Auth-API
   • Converte e-mail  → id numérico  (via userResolver)
   • Publica na exchange “chat” (topic) com routing-key channel.<idSend>.<idReceive>
   • (opcional) método legado para Redis / endpoint /message/worker
---------------------------------------------------------------- */

const axios = require('axios');
const { getChannel } = require('../rabbit');
const { getUserId } = require('./userResolver');

const AUTH_API_BASE_URL   = process.env.AUTH_API_URL   || 'http://nginx-auth';
const RECORD_API_BASE_URL = process.env.RECORD_API_URL || 'http://record-api:5000';

class MessageService {
  constructor(redisClient) {
    this.redisClient = redisClient;                // usado só pelo método legado
  }

  /* -------------------------------------------------- JWT check */
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

  /* -------------------------------------------------- Enfileirar */
  async sendMessageToQueue(userIdSendRaw, userIdReceiveRaw, message, token) {
    /* 1. e-mail (ou string) → id numérico */
    const userIdSend    = await getUserId(userIdSendRaw,    token);   // ex.: 2
    const userIdReceive = await getUserId(userIdReceiveRaw, token);   // ex.: 5

    /* 2. payload + routing-key */
    const payload    = { userIdSend, userIdReceive, message };
    const routingKey = `channel.${userIdSend}.${userIdReceive}`;

    try {
      /* 3. publish na exchange topic “chat” */
      const ch = await getChannel();
      await ch.assertExchange('chat', 'topic', { durable: true });
      ch.publish('chat', routingKey, Buffer.from(JSON.stringify(payload)), {
        persistent: true
      });

      console.log(`📤 Rabbit publish → ${routingKey}`);
      return { success: true };
    } catch (err) {
      console.error('Rabbit publish error:', err);
      return { success: false, error: err.message };
    }
  }

  /* -------------------------------------- (legado) Redis → RecordAPI */
  async processMessagesFromQueueToDB(userIdSend, userIdReceive) {
    const queueName = `queue:${userIdSend}_${userIdReceive}`;
    let processed = 0;
    try {
      while (true) {
        const raw = await this.redisClient.rPop(queueName);
        if (!raw) break;
        const msg = JSON.parse(raw);
        const resp = await axios.post(`${RECORD_API_BASE_URL}/message`, msg);
        if (resp.status === 201) processed++;
      }
      return { success: true, message: `Processed ${processed}` };
    } catch (e) {
      return { success: false, error: e.message };
    }
  }
}

module.exports = MessageService;