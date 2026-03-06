const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { EventEmitter } = require('events');
const { createApp } = require('../src/server');
const { enqueue, getQueueHealth, resetQueueState, getJobLogs } = require('../src/queue/jobQueue');
const { handlers } = require('../src/jobs');
const { registerSystemEvents } = require('../src/events/systemEvents');
const { validateEnv } = require('../src/config/validateEnv');

const env = {
  OPENAI_API_KEY: 'test-openai',
  BF_SERVER_API: 'http://api.example.test',
  MAYA_SECRET: 'maya-test-secret',
};

test.afterEach(() => {
  resetQueueState();
});

test('queue executes jobs and prevents duplicates', async () => {
  const executed = [];
  const added = await enqueue({ id: 'job-1', type: 'document_ocr', payload: { documentId: 'doc-1', documentUrl: 'https://doc', entityId: 'doc-1' } }, {
    handlers: {
      document_ocr: async (payload) => executed.push(payload.documentId),
    },
  });

  const duplicate = await enqueue({ id: 'job-1b', type: 'document_ocr', payload: { documentId: 'doc-1', documentUrl: 'https://doc', entityId: 'doc-1' } }, {
    handlers: {
      document_ocr: async (payload) => executed.push(payload.documentId),
    },
  });

  assert.equal(added, true);
  assert.equal(duplicate, false);

  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.deepEqual(executed, ['doc-1']);
});

test('retry logic retries 3 times before success', async () => {
  let attempts = 0;
  const delays = [];
  await enqueue({ id: 'job-retry', type: 'application_summary', payload: { entityId: 'app-1' } }, {
    handlers: {
      application_summary: async () => {
        attempts += 1;
        if (attempts < 4) throw new Error('temporary');
      },
    },
    delay: async (ms) => {
      delays.push(ms);
    },
  });

  await new Promise((resolve) => setTimeout(resolve, 25));
  assert.equal(attempts, 4);
  assert.deepEqual(delays, [1000, 2000, 3000]);
});

test('core job types are registered', () => {
  assert.ok(handlers.document_ocr);
  assert.ok(handlers.bank_statement_analysis);
  assert.ok(handlers.application_summary);
  assert.ok(handlers.offer_notification);
  assert.ok(handlers.message_notification);
});

test('event listeners enqueue expected jobs', async () => {
  const seenTypes = [];
  const eventBus = new EventEmitter();
  registerSystemEvents(eventBus, {
    enqueue: async (job) => {
      seenTypes.push(job.type);
    },
  });

  eventBus.emit('document_uploaded', { documentType: 'bank_statement' });
  eventBus.emit('documents_complete', { applicationId: 'app-2' });
  eventBus.emit('offer_created', { offerId: 'offer-1' });
  eventBus.emit('message_received', { messageId: 'msg-1' });

  await new Promise((resolve) => setTimeout(resolve, 0));

  assert.equal(seenTypes.length, 5);
  assert.ok(seenTypes.includes('document_ocr'));
  assert.ok(seenTypes.includes('bank_statement_analysis'));
  assert.ok(seenTypes.includes('application_summary'));
  assert.ok(seenTypes.includes('offer_notification'));
  assert.ok(seenTypes.includes('message_notification'));
});

test('health endpoint returns queue metadata', async () => {
  const app = createApp({ ...env, MAYA_VALIDATE_ENV: 'true' });
  const res = await request(app).get('/maya/health').expect(200);
  assert.equal(res.body.status, 'ok');
  assert.equal(res.body.workers, 1);
  assert.equal(typeof res.body.queue_length, 'number');
  assert.deepEqual(res.body, getQueueHealth());
});

test('env validation fails when required env vars are missing', () => {
  assert.throws(() => validateEnv({ OPENAI_API_KEY: 'x', BF_SERVER_API: 'y' }), /MAYA_SECRET missing/);
});

test('job logger records completion and failures', async () => {
  await enqueue({ id: 'job-fail', type: 'message_notification', payload: { entityId: 'msg-fail' } }, {
    handlers: {
      message_notification: async () => {
        throw new Error('boom');
      },
    },
    delay: async () => {},
  });

  await new Promise((resolve) => setTimeout(resolve, 20));

  const logs = getJobLogs();
  const statuses = logs.filter((entry) => ['started', 'failed'].includes(entry.status)).map((entry) => entry.status);
  assert.ok(statuses.includes('started'));
  assert.ok(statuses.includes('failed'));
});
