const axios = require('axios');
const AUTH_API = process.env.AUTH_API_URL || 'http://nginx-auth';

const cache = new Map();
async function getUserId(identifier, token) {
  if (/^\d+$/.test(identifier)) return Number(identifier);
  if (cache.has(identifier)) return cache.get(identifier);

  const { data } = await axios.get(`${AUTH_API}/user`, {
    params : { email: identifier },
    headers: token ? { Authorization: `Bearer ${token}` } : {}
  });
  if (!data?.id) throw new Error('User not found');
  cache.set(identifier, data.id);
  return data.id;
}
module.exports = { getUserId };
