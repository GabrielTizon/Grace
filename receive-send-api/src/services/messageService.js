const jwt = require('jsonwebtoken');
const axios = require('axios');
const { getChannel } = require('../rabbit');
const { getUserId } = require('./userResolver');

const AUTH_API_BASE_URL = process.env.AUTH_API_URL || 'http://nginx-auth:80';
const RECORD_API_BASE_URL = process.env.RECORD_API_URL || 'http://record-api:5000';

class MessageService {
    constructor(redisClient) {
        this.redisClient = redisClient;
        this.jwtSecret = process.env.JWT_SECRET || 'your_fallback_secret_key_receive_send';
    }

    async verifyTokenWithAuthAPI(token, userIdentifier) {
        if (!token || !userIdentifier) return false;
        try {
            const response = await axios.get(`${AUTH_API_BASE_URL}/token`, {
                headers: { 'Authorization': `Bearer ${token}` },
                params: { 'userIdentifier': userIdentifier }
            });
            return response.data && response.data.auth === true;
        } catch (error) {
            console.error('Error verifying token with Auth-API:', error.response ? error.response.data : error.message);
            return false;
        }
    }

    async recordMessageWithRecordAPI(userIdSend, userIdReceive, message) {
        try {
            const payload = { userIdSend, userIdReceive, message };
            const response = await axios.post(`${RECORD_API_BASE_URL}/message`, payload);
            return response.status === 201 && response.data && response.data.ok === true;
        } catch (error) {
            console.error('Error recording message with Record-API:', error.response ? error.response.data : error.message);
            return false;
        }
    }
    
    async getAllUsersFromAuthAPI(token) {
        try {
            const response = await axios.get(`${AUTH_API_BASE_URL}/user?all=true`, {
                headers: { 'Authorization': `Bearer ${token}` }
            });
            return response.data;
        } catch (error) {
            console.error('Error fetching all users from Auth-API:', error.response ? error.response.data : error.message);
            return null;
        }
    }

    async getMessagesFromRecordAPIForChannel(user1, user2, token) {
        try {
            const response = await axios.get(`${RECORD_API_BASE_URL}/messages_for_channel/${user1}/${user2}`, {
                 headers: { 'Authorization': `Bearer ${token}` }
            });
            return response.data.messages || [];
        } catch (error) {
            console.error(`Error fetching messages for channel ${user1}-${user2} from Record-API:`, error.response ? error.response.data : error.message);
            return [];
        }
    }

    async sendMessageToQueue(userIdSendRaw, userIdReceiveRaw, message, token) {
    const ch = await getChannel();
    await ch.assertExchange('chat', 'topic', { durable: true });
    const routingKey = `channel.${idSend}.${idReceive}`;
    ch.publish('chat', routingKey, Buffer.from(JSON.stringify(payload)), { persistent: true });    
    // converte e-mail → id numérico
    const userIdSend    = await getUserId(userIdSendRaw,    token);
    const userIdReceive = await getUserId(userIdReceiveRaw, token);

  const queue = `channel.${userIdSend}.${userIdReceive}`;
    try {
        const ch = await getChannel();
        const queue = `channel.${userIdSend}.${userIdReceive}`;
        await ch.assertQueue(queue, { durable: true });
        const payload = Buffer.from(JSON.stringify({ userIdSend, userIdReceive, message }));
        ch.sendToQueue(queue, payload, { persistent: true });
        return { success: true };
    } catch (err) {
        console.error('RabbitMQ publish error:', err);
        return { success: false, error: err.message };
    }
    }

    async processMessagesFromQueueToDB(userIdSend, userIdReceive) {
        const queueName = `queue:${userIdSend}_${userIdReceive}`;
        let processedCount = 0;
        try {
            while (true) {
                const rawMessageData = await this.redisClient.rPop(queueName);
                if (!rawMessageData) {
                    break;
                }
                const messageData = JSON.parse(rawMessageData);
                
                const recorded = await this.recordMessageWithRecordAPI(
                    messageData.userIdSend,
                    messageData.userIdReceive,
                    messageData.message
                );

                if (recorded) {
                    processedCount++;
                    console.log(`Message from ${messageData.userIdSend} to ${messageData.userIdReceive} moved to DB.`);
                } else {
                    console.error(`Failed to record message ${JSON.stringify(messageData)} to DB. Re-queuing.`);
                    await this.redisClient.lPush(queueName, rawMessageData); 
                    break; 
                }
            }
            return { success: true, message: `Processed ${processedCount} messages from queue ${queueName}.` };
        } catch (error) {
            console.error(`Error processing queue ${queueName}:`, error);
            return { success: false, error: `Failed to process queue ${queueName}.` };
        }
    }
}

module.exports = MessageService;