const jwt = require('jsonwebtoken');

class MessageService {
    constructor(redisClient) {
        this.redisClient = redisClient;
        this.jwtSecret = 'secret_key';
    }

    async sendMessage(token, message, recipient) {
        // Verify JWT
        jwt.verify(token, this.jwtSecret);
        
        const cacheKey = `messages:${recipient}`;
        // Store in Redis (cache)
        await this.redisClient.lPush(cacheKey, message);
        await this.redisClient.expire(cacheKey, 3600); // Cache for 1 hour
        return { message: 'Message sent' };
    }

    async receiveMessages(user) {
        const cacheKey = `messages:${user}`;
        // Retrieve from Redis (cache)
        const messages = await this.redisClient.lRange(cacheKey, 0, -1);
        return messages.length ? messages : [];
    }
}

module.exports = { MessageService };