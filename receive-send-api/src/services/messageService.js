// receive-send-api/src/services/messageService.js

const axios = require('axios');
const { getChannel } = require('../rabbit');
const { getUserId } = require('./userResolver');

const AUTH_API_BASE_URL   = process.env.AUTH_API_URL   || 'http://nginx-auth';
const RECORD_API_BASE_URL = process.env.RECORD_API_BASE_URL || 'http://record-api:5000';

class MessageService {
  constructor(redisClient) {
    this.redisClient = redisClient;
  }

  /* ----------------------------------------------------------
     1) Verificar token JWT junto à Auth-API
  ---------------------------------------------------------- */
  async verifyTokenWithAuthAPI(token, userIdentifier) {
    if (!token || !userIdentifier) return false;
    try {
      const { data } = await axios.get(`${AUTH_API_BASE_URL}/token`, {
        headers: { Authorization: `Bearer ${token}` },
        params: { userIdentifier }
      });
      return data?.auth === true;
    } catch (e) {
      console.error('Auth-API verify error:', e.response?.data || e.message);
      return false;
    }
  }

  /* ----------------------------------------------------------
     2) Buscar todos os usuários na Auth-API (GET /user?all=true)
     → Retorna um array [{ id, name, lastName, email, ...}, …]
  ---------------------------------------------------------- */
  async getAllUsersFromAuthAPI(token) {
    if (!token) return null;
    try {
      const response = await axios.get(`${AUTH_API_BASE_URL}/user?all=true`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      return response.data;  // espera que seja um array de usuários
    } catch (error) {
      console.error('Error fetching all users from Auth-API:', 
                    error.response?.data || error.message);
      return null;
    }
  }

  /* ----------------------------------------------------------
     3) Buscar mensagens de um canal específico via Record-API
     → GET /messages_for_channel/:user1/:user2
  ---------------------------------------------------------- */
    async getMessagesFromRecordAPIForChannel(userIdRaw1, userIdRaw2, token) {
      try {
        // converte e-mail → id numérico
        const id1 = await getUserId(userIdRaw1, token);
        const id2 = await getUserId(userIdRaw2, token);

        const { data } = await axios.get(
          `${RECORD_API_BASE_URL}/messages_for_channel/${id1}/${id2}`,
          { headers: { Authorization: `Bearer ${token}` } }
        );
        return data.messages || [];
      } catch (error) {
        console.error(
          `Record-API channel ${userIdRaw1}-${userIdRaw2} error:`,
          error.response?.data || error.message
        );
        return [];
      }
    }

  /* ----------------------------------------------------------
     4) Enfileirar mensagem no RabbitMQ (tópico “chat” / routing-key channel.X.Y)
     → Converte e-mail (ou string) → ID numérico em Auth-API
  ---------------------------------------------------------- */
  async sendMessageToQueue(userIdSendRaw, userIdReceiveRaw, message, token) {
    // Primeiro converte o userIdentifier (string) para id numérico
    const userIdSend    = await getUserId(userIdSendRaw, token);
    const userIdReceive = await getUserId(userIdReceiveRaw, token);

    const payload    = { userIdSend, userIdReceive, message };
    const routingKey = `channel.${userIdSend}.${userIdReceive}`;

    try {
      const ch = await getChannel();
      await ch.assertExchange('chat', 'topic', { durable: true });
      ch.publish('chat', routingKey, Buffer.from(JSON.stringify(payload)), {
        persistent: true
      });
      console.log(`📤 RabbitMQ publish → ${routingKey}`);
      return { success: true };
    } catch (err) {
      console.error('RabbitMQ publish error:', err);
      return { success: false, error: err.message };
    }
  }

  /* ----------------------------------------------------------
     5) (LEGADO) Processar fila Redis e enviar para Record-API
     → Esse método é usado pelo endpoint POST /message/worker
  ---------------------------------------------------------- */
  async processMessagesFromQueueToDB(userIdSend, userIdReceive) {
    const queueName = `queue:${userIdSend}_${userIdReceive}`;
    let processed = 0;
    try {
      while (true) {
        const raw = await this.redisClient.rPop(queueName);
        if (!raw) break;
        const msgObj = JSON.parse(raw);
        const resp = await axios.post(
          `${RECORD_API_BASE_URL}/message`,
          msgObj
        );
        if (resp.status === 201) processed++;
      }
      return { success: true, message: `Processed ${processed} messages` };
    } catch (e) {
      console.error('Error in processMessagesFromQueueToDB:', e.message);
      return { success: false, error: e.message };
    }
  }
}

module.exports = MessageService;
