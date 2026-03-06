const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const twilio = require('twilio');
const { createApp, STATUS_MAP } = require('../src/server');

const env = {
  TWILIO_ACCOUNT_SID: 'AC123',
  TWILIO_AUTH_TOKEN: 'auth',
  TWILIO_API_KEY: 'SK123',
  TWILIO_API_SECRET: 'secret',
  TWILIO_TWIML_APP_SID: 'AP123',
  OPENAI_API_KEY: 'test-openai',
  BF_SERVER_API: 'http://api.example.test',
  MAYA_SECRET: 'maya-test-secret',
};

const auth = (id, role) => `Bearer ${Buffer.from(JSON.stringify({ id, role })).toString('base64')}`;

test('token auth/role and success with request id', async () => {
  const app = createApp(env);
  await request(app).post('/api/voice/token').expect(401);
  await request(app).post('/api/voice/token').set('Authorization', auth('u1', 'viewer')).expect(403);
  const ok = await request(app)
    .post('/api/voice/token')
    .set('Authorization', auth('u1', 'staff'))
    .set('x-request-id', 'rid-token')
    .expect(200);
  assert.equal(ok.body.identity, 'staff:u1');
  assert.ok(ok.body.token);
  assert.equal(ok.body.requestId, 'rid-token');
  assert.equal(ok.headers['x-request-id'], 'rid-token');
});

test('presence heartbeat and /api/voice/call rings assigned first then fallback', async () => {
  const ringAttempts = [];
  const app = createApp(env, {
    findAssignedStaffId: async () => 'a1',
    ringStaffLeg: async ({ staffId }) => {
      const sid = `CA_${staffId}_${ringAttempts.length}`;
      ringAttempts.push(staffId);
      return { sid };
    },
  });

  await request(app)
    .post('/api/voice/presence/heartbeat')
    .set('Authorization', auth('a1', 'staff'))
    .send({ source: 'dialer', status: 'online' })
    .expect(200);

  await request(app)
    .post('/api/voice/presence/heartbeat')
    .set('Authorization', auth('a2', 'staff'))
    .send({ source: 'portal', status: 'online' })
    .expect(200);

  const started = await request(app)
    .post('/api/voice/call')
    .set('Authorization', auth('dispatcher', 'admin'))
    .send({ fromIdentity: 'client:c-1', toClientId: 'c-1' })
    .expect(200);

  assert.equal(started.body.callSession.assignedStaffId, 'a1');
  assert.deepEqual(ringAttempts, ['a1']);
});

test('answered status cancels other ringing legs', async () => {
  const canceledSids = [];
  let sidCount = 0;
  const app = createApp(env, {
    findAssignedStaffId: async () => null,
    ringStaffLeg: async ({ staffId }) => ({ sid: `CA_${staffId}_${++sidCount}` }),
    cancelRingLeg: async ({ sid }) => {
      canceledSids.push(sid);
      return true;
    },
  });

  await request(app)
    .post('/api/voice/presence/heartbeat')
    .set('Authorization', auth('a1', 'staff'))
    .send({ source: 'dialer', status: 'online' })
    .expect(200);

  await request(app)
    .post('/api/voice/presence/heartbeat')
    .set('Authorization', auth('a2', 'staff'))
    .send({ source: 'portal', status: 'online' })
    .expect(200);

  await request(app)
    .post('/api/voice/call')
    .set('Authorization', auth('dispatcher', 'admin'))
    .send({ fromIdentity: 'client:c-2', toClientId: 'c-2' })
    .expect(200);

  const body = { CallSid: 'CA_a1_1', CallStatus: 'answered' };
  const url = 'http://127.0.0.1/api/voice/status';
  const sig = twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, body);
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', sig)
    .send(body)
    .expect(200);

  assert.deepEqual(canceledSids, ['CA_a2_2']);
});

test('503 when voice disabled except webhook', async () => {
  const app = createApp({ ...env, VOICE_ENABLED: 'false' });
  await request(app).post('/api/voice/token').set('Authorization', auth('u1', 'staff')).expect(503);
  await request(app)
    .post('/api/voice/calls/start')
    .set('Authorization', auth('u1', 'staff'))
    .send({ clientCallId: 'c-disabled', to: '+1' })
    .expect(503);
  await request(app)
    .post('/api/voice/calls/end')
    .set('Authorization', auth('u1', 'staff'))
    .send({ id: 'missing' })
    .expect(503);
  await request(app)
    .get('/api/voice/calls/missing')
    .set('Authorization', auth('u1', 'staff'))
    .expect(503);

  const body = { CallSid: 'CA1', CallStatus: 'queued', clientCallId: 'c-disabled' };
  const url = 'http://127.0.0.1/api/voice/status';
  const sig = twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, body);
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', sig)
    .send(body)
    .expect(200);
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

test('webhook signature validation, idempotency, and lifecycle mapping', async () => {
  const app = createApp(env);
  const started = await request(app)
    .post('/api/voice/calls/start')
    .set('Authorization', auth('u1', 'staff'))
    .send({ clientCallId: 'c2', to: '+1222333' })
    .expect(200);

  await request(app).post('/api/voice/status').send({ CallSid: 'CA1', CallStatus: 'queued', clientCallId: 'c2' }).expect(403);

  const inProgressBody = { CallSid: 'CA1', CallStatus: 'in-progress', clientCallId: 'c2' };
  const url = 'http://127.0.0.1/api/voice/status';
  const inProgressSig = twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, inProgressBody);
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', inProgressSig)
    .send(inProgressBody)
    .expect(200);

  const repeatedSig = twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, inProgressBody);
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', repeatedSig)
    .send(inProgressBody)
    .expect(200);

  const doneBody = { CallSid: 'CA1', CallStatus: 'completed', clientCallId: 'c2' };
  const doneSig = twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, doneBody);
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', doneSig)
    .send(doneBody)
    .expect(200);

  const outOfOrderBody = { CallSid: 'CA1', CallStatus: 'queued', clientCallId: 'c2' };
  const outOfOrderSig = twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, outOfOrderBody);
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', outOfOrderSig)
    .send(outOfOrderBody)
    .expect(200);

  const status = await request(app)
    .get(`/api/voice/calls/${started.body.call.id}`)
    .set('Authorization', auth('u1', 'staff'))
    .expect(200);
  assert.equal(status.body.call.status, 'completed');

  const unknownBody = { CallSid: 'CA-UNKNOWN', CallStatus: 'failed', clientCallId: 'missing' };
  const unknownSig = twilio.getExpectedTwilioSignature(env.TWILIO_AUTH_TOKEN, url, unknownBody);
  await request(app)
    .post('/api/voice/status')
    .set('Host', '127.0.0.1')
    .set('X-Twilio-Signature', unknownSig)
    .send(unknownBody)
    .expect(200);
});

test('timeout safety marks call failed and returns 504', async () => {
  const app = createApp(env, {
    startTwilioCall: async () => new Promise((resolve) => setTimeout(() => resolve({ sid: 'CADELAY' }), 4500)),
  });

  const res = await request(app)
    .post('/api/voice/calls/start')
    .set('Authorization', auth('u-timeout', 'staff'))
    .send({ clientCallId: 'c-timeout', to: '+1222333' })
    .expect(504);

  assert.equal(res.body.code, 'upstream_timeout');
  assert.ok(res.body.requestId);
});

test('twiml endpoint returns XML', async () => {
  const app = createApp(env);
  const res = await request(app).post('/api/twilio/voice').expect(200);
  assert.match(res.headers['content-type'], /text\/xml/);
  assert.match(res.text, /<Response>/);
  assert.match(res.text, /<Dial>/);
});

test('status map includes failed and canceled', () => {
  assert.equal(STATUS_MAP.failed, 'failed');
  assert.equal(STATUS_MAP.canceled, 'failed');
});
