const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const twilio = require('twilio');
const { createApp } = require('../src/server');

const env = {
  TWILIO_ACCOUNT_SID: 'AC123',
  TWILIO_AUTH_TOKEN: 'auth',
  TWILIO_API_KEY: 'SK123',
  TWILIO_API_SECRET: 'secret',
  TWILIO_TWIML_APP_SID: 'AP123',
};

const auth = (id, role) => `Bearer ${Buffer.from(JSON.stringify({ id, role })).toString('base64')}`;

test('token auth/role and success', async () => {
  const app = createApp(env);
  await request(app).post('/api/voice/token').expect(401);
  await request(app).post('/api/voice/token').set('Authorization', auth('u1', 'viewer')).expect(403);
  const ok = await request(app).post('/api/voice/token').set('Authorization', auth('u1', 'staff')).expect(200);
  assert.equal(ok.body.identity, 'u1');
  assert.ok(ok.body.token);
});

test('503 when voice disabled', async () => {
  const app = createApp({});
  await request(app).post('/api/voice/token').set('Authorization', auth('u1', 'staff')).expect(503);
});

test('start idempotent and ownership guard end/status', async () => {
  const app = createApp(env);
  const first = await request(app)
    .post('/api/voice/calls/start')
    .set('Authorization', auth('u1', 'staff'))
    .send({ clientCallId: 'c1', to: '+1222333' })
    .expect(200);
  const second = await request(app)
    .post('/api/voice/calls/start')
    .set('Authorization', auth('u1', 'staff'))
    .send({ clientCallId: 'c1', to: '+1222333' })
    .expect(200);
  assert.equal(first.body.call.id, second.body.call.id);

  await request(app)
    .post('/api/voice/calls/end')
    .set('Authorization', auth('u2', 'staff'))
    .send({ id: first.body.call.id })
    .expect(403);

  await request(app)
    .post('/api/voice/calls/end')
    .set('Authorization', auth('u1', 'staff'))
    .send({ id: first.body.call.id })
    .expect(200);

  await request(app)
    .get(`/api/voice/calls/${first.body.call.id}`)
    .set('Authorization', auth('u2', 'staff'))
    .expect(403);
});

test('webhook signature validation and lifecycle mapping', async () => {
  const app = createApp(env);
  const started = await request(app)
    .post('/api/voice/calls/start')
    .set('Authorization', auth('u1', 'staff'))
    .send({ clientCallId: 'c2', to: '+1222333' })
    .expect(200);

  await request(app).post('/api/voice/status').send({ CallSid: 'CA1', CallStatus: 'queued', clientCallId: 'c2' }).expect(403);

  const body = { CallSid: 'CA1', CallStatus: 'in-progress', clientCallId: 'c2' };
  const url = 'http://127.0.0.1/api/voice/status';
  const sig = twilio.validateRequest ? twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, body) : '';
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', sig)
    .send(body)
    .expect(200);

  const status = await request(app)
    .get(`/api/voice/calls/${started.body.call.id}`)
    .set('Authorization', auth('u1', 'staff'))
    .expect(200);
  assert.equal(status.body.call.status, 'active');
});
