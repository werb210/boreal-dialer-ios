import test from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import jwt from 'jsonwebtoken';
import { createApp } from '../src/server.js';

class RedisMock { async get(){return null;} async set(){} multi(){return { set(){return this;}, sadd(){return this;}, zadd(){return this;}, hset(){return this;}, exec: async()=>[]};} }

const env = {
  NODE_ENV: 'test',
  TWILIO_ACCOUNT_SID: 'AC123',
  TWILIO_AUTH_TOKEN: 'auth',
  TWILIO_API_KEY: 'SK123',
  TWILIO_API_SECRET: 'secret',
  TWILIO_VOICE_APP_SID: 'AP123',
  VERIFIED_TWILIO_NUMBER: '+15551230000',
  REDIS_URL: 'redis://localhost:6379',
  BF_JWT_SECRET: 'jwt_secret',
  ALLOWED_ORIGINS: 'http://localhost:3000',
};
const auth = (id, role) => `Bearer ${jwt.sign({ id, role }, env.BF_JWT_SECRET)}`;

test('voice token includes outgoing application sid grant', async () => {
  const app = createApp(env, { redis: new RedisMock(), logger: { info() {} } });
  const res = await request(app).post('/api/voice/token').set('Authorization', auth('u1', 'staff')).expect(200);
  assert.equal(typeof res.body.token, 'string');
  const payload = JSON.parse(Buffer.from(res.body.token.split('.')[1], 'base64url').toString('utf8'));
  assert.equal(payload.grants.identity, 'u1');
  assert.equal(payload.grants.voice.outgoing.application_sid, env.TWILIO_VOICE_APP_SID);
});

test('voice twiml includes answerOnBridge and callerId', async () => {
  const app = createApp(env, { redis: new RedisMock(), logger: { info() {} } });
  const res = await request(app).post('/api/voice/twiml').send({ To: '+15557654321' }).expect(200);
  assert.match(res.text, /answerOnBridge="true"/);
  assert.match(res.text, /callerId="\+15551230000"/);
  assert.match(res.text, /<Number>\+15557654321<\/Number>/);
});
