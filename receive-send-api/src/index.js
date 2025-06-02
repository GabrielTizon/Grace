const express = require('express');
const jwt = require('jsonwebtoken');
const redis = require('redis');

const app = express();
app.use(express.json());

const redisClient = redis.createClient({
    url: `redis://${process.env.REDIS_HOST}:6379`
});

(async () => {
    try {
        await redisClient.connect();
        console.log('✅ Redis connected');
    } catch (err) {
        console.error('❌ Redis connection failed:', err);
        process.exit(1);
    }
})();

// Healthcheck endpoint para o Docker e testes
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok' });
});

// Opcional: rota raiz para testes básicos
app.get('/', (req, res) => {
    res.send('Receive-Send API is running');
});

app.post('/send', async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'JWT must be provided' });
    }

    const token = authHeader.split(' ')[1];

    try {
        const secret = process.env.JWT_SECRET;
        if (!secret) {
            console.error('❌ JWT_SECRET not set in environment variables');
            return res.status(500).json({ error: 'JWT secret not configured' });
        }

        const decoded = jwt.verify(token, secret, { algorithms: ['HS256'] });
        console.log('✅ JWT decoded:', decoded);

        const message = req.body.message;
        if (!message || typeof message !== 'string') {
            return res.status(400).json({ error: 'Message required and must be a string' });
        }

        await redisClient.lPush('messages', message);
        console.log(`📥 Message pushed to Redis: ${message}`);
        return res.status(200).json({ status: 'Message sent' });

    } catch (err) {
        console.error('❌ JWT validation error:', err.message);
        return res.status(401).json({ error: 'Invalid JWT', details: err.message });
    }
});

const PORT = 3000;
app.listen(PORT, () => {
    console.log(`🚀 Server running on port ${PORT}`);
});
