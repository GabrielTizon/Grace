const express = require('express');
const jwt = require('jsonwebtoken');
const redis = require('redis');

const app = express();
app.use(express.json());

const redisClient = redis.createClient({
    url: `redis://${process.env.REDIS_HOST}:6379`
});
redisClient.connect().catch(console.error);

app.post('/send', (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'JWT must be provided' });
    }

    const token = authHeader.split(' ')[1];
    try {
        const decoded = jwt.verify(token, 'your_secret_key', { algorithms: ['HS256'] });
        console.log('JWT decoded:', decoded);
        const message = req.body.message;
        if (message) {
            redisClient.lPush('messages', message);
            res.json({ status: 'Message sent' });
        } else {
            res.status(400).json({ error: 'Message required' });
        }
    } catch (err) {
        console.error('JWT validation error:', err.message);
        res.status(401).json({ error: 'Invalid JWT', details: err.message });
    }
});

app.listen(3000, () => console.log('Running on port 3000'));