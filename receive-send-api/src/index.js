const express = require('express');
const jwt = require('jsonwebtoken');
const redis = require('redis');
const MessageService = require('./services/messageService');

const app = express();
app.use(express.json());

const redisClient = redis.createClient({
    url: `redis://${process.env.REDIS_HOST || 'redis'}:6379`
});

const messageService = new MessageService(redisClient);

(async () => {
    try {
        await redisClient.connect();
        console.log('✅ Receive-Send-API: Redis connected');
    } catch (err) {
        console.error('❌ Receive-Send-API: Redis connection failed:', err);
        process.exit(1);
    }
})();

const extractToken = (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
        req.token = authHeader.split(' ')[1];
    } else {
        req.token = null;
    }
    next();
};

app.use(extractToken);

app.get('/health', (req, res) => {
    res.status(200).json({ status: 'Receive-Send-API is OK' });
});
app.get('/', (req, res) => res.send('Receive-Send API is running'));

app.post('/message', async (req, res) => {
    const { userIdSend, userIdReceive, message } = req.body;
    const token = req.token;

    if (!token) {
        return res.status(401).json({ msg: 'not auth', error: 'Token required' });
    }
    if (!userIdSend || !userIdReceive || !message) {
        return res.status(400).json({ error: 'userIdSend, userIdReceive, and message are required' });
    }

    const isAuthenticated = await messageService.verifyTokenWithAuthAPI(token, userIdSend);
    if (!isAuthenticated) {
        return res.status(401).json({ msg: 'not auth', error: 'Token validation failed or user mismatch' });
    }

    const enqueueResult = await messageService.sendMessageToQueue(userIdSend, userIdReceive, message);
    if (!enqueueResult.success) {
        return res.status(500).json({ error: 'Failed to enqueue message', details: enqueueResult.error });
    }
    
    return res.status(201).json({ message: 'mesage sended with success' });
});

app.post('/message/worker', async (req, res) => {
    const { userIdSend, userIdReceive } = req.body;
    const token = req.token;
    
    if (!token) {
        return res.status(401).json({ msg: 'not auth', error: 'Token required for worker' });
    }
    try {
        jwt.verify(token, process.env.JWT_SECRET || 'your_fallback_secret_key_receive_send');
    } catch (e) {
        return res.status(401).json({ msg: 'not auth', error: 'Invalid token for worker: ' + e.message });
    }

    if (!userIdSend || !userIdReceive) {
        return res.status(400).json({ error: 'userIdSend and userIdReceive are required to identify the queue' });
    }

    const result = await messageService.processMessagesFromQueueToDB(userIdSend, userIdReceive);

    if (result.success) {
        return res.status(200).json({ msg: 'ok', details: result.message });
    } else {
        return res.status(500).json({ msg: 'worker error', error: result.error });
    }
});

app.get('/message', async (req, res) => {
    const requestingUserIdentifier = req.query.user;
    const token = req.token;

    if (!token) {
        return res.status(401).json({ msg: 'not auth', error: 'Token required' });
    }
    if (!requestingUserIdentifier) {
        return res.status(400).json({ error: 'Query parameter "user" is required' });
    }

    const isAuthenticated = await messageService.verifyTokenWithAuthAPI(token, requestingUserIdentifier);
    if (!isAuthenticated) {
        return res.status(401).json({ msg: 'not auth', error: 'Token validation failed for requesting user' });
    }

    const allUsers = await messageService.getAllUsersFromAuthAPI(token);
    if (!allUsers || !Array.isArray(allUsers)) {
        return res.status(500).json({ error: 'Failed to fetch users from Auth-API or invalid format' });
    }
    
    let allFormattedMessages = [];
    for (const targetUser of allUsers) {
        const targetUserIdentifier = targetUser.email || targetUser.username; 
        if (!targetUserIdentifier || targetUserIdentifier === requestingUserIdentifier) continue;

        const channelMessages = await messageService.getMessagesFromRecordAPIForChannel(targetUserIdentifier, requestingUserIdentifier, token);
        
        channelMessages.forEach(msg => {
            allFormattedMessages.push({
                userId: msg.userIdSend,
                msg: msg.message,
            });
        });
    }
    
    
    return res.status(200).json(allFormattedMessages);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 Receive-Send-API Server running on port ${PORT}`);
});