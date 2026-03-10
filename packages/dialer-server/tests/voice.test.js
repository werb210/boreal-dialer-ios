import test from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import jwt from 'jsonwebtoken';
import { createApp } from '../src/server.js';

class RedisMock {
  constructor() { this.kv = new Map(); this.hash = new Map(); this.sets = new Map(); this.z = new Map(); }
  multi() { const ops = []; const self = this; const chain = { set: (...a) => (ops.push(['set', a]), chain), sadd: (...a) => (ops.push(['sadd', a]), chain), zadd: (...a) => (ops.push(['zadd', a]), chain), hset: (...a) => (ops.push(['hset', a]), chain), exec: async () => { for (const [m, a] of ops) await self[m](...a); return []; } }; return chain; }
  async set(key, value, ex, ttl) { this.kv.set(key, value); if (ex === 'EX') setTimeout(() => this.kv.delete(key), ttl * 1000); }
  async get(key) { return this.kv.get(key) ?? null; }
  async del(key) { this.kv.delete(key); }
  async exists(key) { return this.kv.has(key) ? 1 : 0; }
  async hset(name, field, value) { if (!this.hash.has(name)) this.hash.set(name, new Map()); this.hash.get(name).set(field, value); }
  async hget(name, field) { return this.hash.get(name)?.get(field) ?? null; }
  async sadd(name, value) { if (!this.sets.has(name)) this.sets.set(name, new Set()); this.sets.get(name).add(value); }
  async smembers(name) { return [...(this.sets.get(name) || new Set())]; }
  async srem(name, value) { this.sets.get(name)?.delete(value); }
  async zadd(name, score, member) { if (!this.z.has(name)) this.z.set(name, new Map()); this.z.get(name).set(member, Number(score)); }
  async zrangebyscore(name, min, max) { const z = this.z.get(name) || new Map(); return [...z.entries()].filter(([, s]) => s >= Number(min) && s <= Number(max)).map(([m]) => m); }
  async zrem(name, member) { this.z.get(name)?.delete(member); }
}

const env = {
  NODE_ENV: 'test',
  TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID || 'test_account_sid',
  TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN || 'test_auth_token',
  TWILIO_API_KEY: 'test_api_key',
  TWILIO_API_SECRET: 'test_api_secret',
  TWILIO_TWIML_APP_SID: 'test_app_sid',
  REDIS_URL: 'redis://localhost:6379',
  BF_JWT_SECRET: 'jwt_secret',
  ALLOWED_ORIGINS: 'http://localhost:3000,http://localhost:5173',
};

process.env.NODE_ENV = 'test';
const auth = (id, role) => `Bearer ${jwt.sign({ id, role }, env.BF_JWT_SECRET)}`;

test('JWT auth required and token endpoint works', async () => {
  const app = createApp(env, { redis: new RedisMock() });
  await request(app).post('/api/voice/token').expect(401);
  await request(app).post('/api/voice/token').set('Authorization', auth('u1', 'staff')).expect(200);
});

test('presence + simultaneous ringing still works', async () => {
  const ringAttempts = [];
  const app = createApp(env, {
    redis: new RedisMock(),
    findAssignedStaffId: async () => 'a1',
    ringStaffLeg: async ({ staffId }) => { ringAttempts.push(staffId); return { sid: `CA_${staffId}_${ringAttempts.length}` }; },
  });

  await request(app).post('/api/voice/presence/heartbeat').set('Authorization', auth('a1', 'staff')).send({ source: 'dialer', status: 'online' }).expect(200);
  await request(app).post('/api/voice/presence/heartbeat').set('Authorization', auth('a2', 'staff')).send({ source: 'portal', status: 'online' }).expect(200);

  const started = await request(app).post('/api/voice/call').set('Authorization', auth('dispatcher', 'admin')).send({ fromIdentity: 'client:c-1', toClientId: 'c-1' }).expect(200);
  assert.equal(started.body.callSession.assignedStaffId, 'a1');
  assert.deepEqual(ringAttempts, ['a1']);
});

test('voicemail routing and webhook endpoints unauthenticated', async () => {
  const app = createApp(env, {
    redis: new RedisMock(),
    findAssignedStaffId: async () => null,
    routeToVoicemail: async ({ sessionId }) => ({ voicemailUrl: `mock://${sessionId}` }),
  });

  await request(app).post('/api/voice/status').send({ CallSid: 'CA_none', CallStatus: 'completed' }).expect(200);
  await request(app).post('/api/voice/recording').send({ CallSid: 'CA_none' }).expect(200);
});
