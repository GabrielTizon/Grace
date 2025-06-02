class MessageService {
    constructor(redisClient) {
        this.redisClient = redisClient;
        this.jwtSecret = process.env.JWT_SECRET || 'secret_key'; // fallback
    }

    async sendMessage(token, message, recipient) {
        jwt.verify(token, this.jwtSecret);
        const cacheKey = `messages:${recipient}`;
        await this.redisClient.lPush(cacheKey, message);
        await this.redisClient.expire(cacheKey, 3600);
        return { message: 'Message sent' };
    }

    async receiveMessages(user) {
        const cacheKey = `messages:${user}`;
        const messages = await this.redisClient.lRange(cacheKey, 0, -1);
        return messages.length ? messages : [];
    }
}
