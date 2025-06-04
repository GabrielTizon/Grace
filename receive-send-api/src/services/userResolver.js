const axios = require('axios');
const AUTH_API = process.env.AUTH_API_URL || 'http://nginx-auth';

const idCache = new Map();              // cache simples em memória

async function getUserId(identifier, token) {
  // se já é número, devolve
  if (/^\d+$/.test(identifier)) return Number(identifier);

  // tenta cache
  if (idCache.has(identifier)) return idCache.get(identifier);

  // consulta Auth-API
  const { data } = await axios.get(`${AUTH_API}/user`, {
    params: { email: identifier },
    headers: token ? { Authorization: `Bearer ${token}` } : {}
  });
  if (!data || !data.id) throw new Error('User not found');

  idCache.set(identifier, data.id);     // grava no cache
  return data.id;
}

module.exports = { getUserId };
