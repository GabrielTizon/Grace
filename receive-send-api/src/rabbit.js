const amqplib = require('amqplib');

let channel;

async function getChannel() {
  if (channel) return channel;
  const conn = await amqplib.connect({
    protocol: 'amqp',
    hostname: process.env.RABBITMQ_HOST,
    username: process.env.RABBITMQ_USER,
    password: process.env.RABBITMQ_PASS,
  });
  channel = await conn.createChannel();
  return channel;
}

module.exports = { getChannel };