const express = require('express');
const crypto = require('crypto');
const twilio = require('twilio');
const http = require('http');

const STATUS_MAP = {
  completed: 'completed',
  'in-progress': 'active',
  failed: 'failed',
  busy: 'failed',
  'no-answer': 'failed',
  canceled: 'failed',
};

const TERMINAL_STATUSES = new Set(['completed', 'failed']);

function normalizeStatus(rawStatus) {
  if (!rawStatus) return 'unknown';
  return STATUS_MAP[String(rawStatus).toLowerCase()] || 'unknown';
}

function isTerminal(status) {
  return TERMINAL_STATUSES.has(status);
}

function makeError(res, req, status, code, message) {
  return res.status(status).json({ code, message, requestId: req.requestId });
}

function timeout(ms) {
  return new Promise((_, reject) => {
    setTimeout(() => reject(new Error('twilio_timeout')), ms);
  });
}

function createInMemoryCallsRepo() {
  const callsById = new Map();
  const callsByClientKey = new Map();
  const callsByApplicationKey = new Map();

  return {
    // Mirrors an atomic DB upsert by unique(user_id, client_call_id).
    upsertCallAtomic({ userId, clientCallId, to, applicationId }) {
      const dedupeKey = `${userId}:${clientCallId}`;
      const existingId = callsByClientKey.get(dedupeKey);
      if (existingId) {
        const existing = callsById.get(existingId);
        existing.updated_at = new Date().toISOString();
        return existing;
      }

      const id = crypto.randomUUID();
      const call = {
        id,
        user_id: userId,
        clientCallId,
        applicationId,
        to,
        status: 'initiated',
        twilioStatus: null,
        sid: null,
        started_at: new Date().toISOString(),
        ended_at: null,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      callsById.set(id, call);
      if (clientCallId) callsByClientKey.set(dedupeKey, id);
      if (applicationId) callsByApplicationKey.set(`${userId}:${applicationId}`, id);
      return call;
    },
    findActiveCall(userId, applicationId) {
      const id = callsByApplicationKey.get(`${userId}:${applicationId}`);
      if (!id) return null;
      const call = callsById.get(id);
      if (!call) return null;
      if (isTerminal(call.status)) return null;
      return call;
    },
    getById(id) {
      return callsById.get(id) || null;
    },
    findBySidOrClientCallId(sid, clientCallId) {
      for (const call of callsById.values()) {
        if ((sid && call.sid === sid) || (clientCallId && call.clientCallId === clientCallId)) {
          return call;
        }
      }
      return null;
    },
  };
}

async function defaultTwilioStartCall(call, env) {
  if (env.MOCK_TWILIO_DELAY_MS) {
    await new Promise((resolve) => setTimeout(resolve, Number(env.MOCK_TWILIO_DELAY_MS)));
  }
  return { sid: `CA${call.id.replace(/-/g, '').slice(0, 30)}` };
}

function createApp(env = process.env, deps = {}) {
  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: false }));

  const callsRepo = deps.callsRepo || createInMemoryCallsRepo();
  const startTwilioCall = deps.startTwilioCall || defaultTwilioStartCall;
  const logger = deps.logger || console;
  const recordingsByCallSid = new Map();

  const voiceEnabled = env.VOICE_ENABLED !== 'false';

  app.use((req, res, next) => {
    req.requestId = req.headers['x-request-id'] || crypto.randomUUID();
    res.setHeader('x-request-id', req.requestId);
    next();
  });

  app.use((req, _res, next) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ')) {
      req.user = null;
      return next();
    }
    try {
      const decoded = JSON.parse(Buffer.from(auth.slice(7), 'base64').toString('utf8'));
      req.user = { id: decoded.id, role: decoded.role };
    } catch {
      req.user = null;
    }
    next();
  });

  function requireAuth(req, res, next) {
    if (!req.user?.id) return makeError(res, req, 401, 'unauthorized', 'Authentication required');
    return next();
  }

  function requireStaff(req, res, next) {
    const role = String(req.user.role || '');
    if (!['Staff', 'staff', 'admin', 'Admin'].includes(role)) {
      return makeError(res, req, 403, 'forbidden', 'forbidden');
    }
    return next();
  }

  function requireVoiceEnabled(req, res, next) {
    if (!voiceEnabled) return makeError(res, req, 503, 'voice_unavailable', 'Voice service is disabled');
    return next();
  }

  app.get('/api/voice/token', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const token = new twilio.jwt.AccessToken(
      env.TWILIO_ACCOUNT_SID,
      env.TWILIO_API_KEY,
      env.TWILIO_API_SECRET,
      { identity: req.user.id }
    );
    token.addGrant(new twilio.jwt.AccessToken.VoiceGrant({ outgoingApplicationSid: env.TWILIO_TWIML_APP_SID }));
    res.status(200).json({ token: token.toJwt(), identity: req.user.id, requestId: req.requestId });
  });

  app.post('/api/voice/token', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const token = new twilio.jwt.AccessToken(
      env.TWILIO_ACCOUNT_SID,
      env.TWILIO_API_KEY,
      env.TWILIO_API_SECRET,
      { identity: req.user.id }
    );
    token.addGrant(new twilio.jwt.AccessToken.VoiceGrant({ outgoingApplicationSid: env.TWILIO_TWIML_APP_SID }));
    res.status(200).json({ token: token.toJwt(), identity: req.user.id, requestId: req.requestId });
  });

  app.post('/api/voice/calls/start', requireAuth, requireStaff, requireVoiceEnabled, async (req, res) => {
    const { clientCallId, to, applicationId } = req.body || {};
    if (!to || (!clientCallId && !applicationId)) return makeError(res, req, 400, 'bad_request', 'missing call identifiers');

    let call = applicationId ? callsRepo.findActiveCall(req.user.id, applicationId) : null;
    if (!call) {
      call = callsRepo.upsertCallAtomic({ userId: req.user.id, clientCallId, to, applicationId });
    }

    try {
      const twilioResult = await Promise.race([
        startTwilioCall(call, env),
        timeout(4000),
      ]);

      if (twilioResult?.sid) call.sid = twilioResult.sid;
      call.updated_at = new Date().toISOString();
      const normalized = normalizeStatus(call.twilioStatus);
      if (normalized !== 'unknown') call.status = normalized;

      logger.info({ event: 'voice_call_started', requestId: req.requestId, callId: call.id, status: call.status });
      return res.status(200).json({ call: { ...call, status: call.status }, requestId: req.requestId });
    } catch {
      call.status = 'failed';
      call.ended_at = call.ended_at || new Date().toISOString();
      call.updated_at = new Date().toISOString();
      return makeError(res, req, 504, 'upstream_timeout', 'Twilio call start timed out');
    }
  });

  app.post('/api/voice/calls/end', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const { id } = req.body || {};
    const call = callsRepo.getById(id);
    if (!call) return makeError(res, req, 404, 'not_found', 'Call not found');
    if (call.user_id !== req.user.id) return makeError(res, req, 403, 'forbidden', 'Call ownership violation');

    if (!isTerminal(call.status)) {
      call.status = 'completed';
      call.ended_at = call.ended_at || new Date().toISOString();
      call.updated_at = new Date().toISOString();
      logger.info({ event: 'voice_call_completed', requestId: req.requestId, callId: call.id, status: call.status });
    }
    return res.status(200).json({ call: { ...call, status: call.status }, requestId: req.requestId });
  });

  app.get('/api/voice/calls/:id', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const call = callsRepo.getById(req.params.id);
    if (!call) return makeError(res, req, 404, 'not_found', 'Call not found');
    if (call.user_id !== req.user.id) return makeError(res, req, 403, 'forbidden', 'Call ownership violation');

    return res.status(200).json({
      call: {
        id: call.id,
        clientCallId: call.clientCallId,
        status: call.status,
        started_at: call.started_at,
        ended_at: call.ended_at,
      },
      requestId: req.requestId,
    });
  });

  app.post('/api/voice/status', (req, res) => {
    const signature = req.headers['x-twilio-signature'];
    if (!signature) return makeError(res, req, 403, 'missing_signature', 'Missing Twilio signature');

    const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
    const valid = twilio.validateRequest(env.TWILIO_AUTH_TOKEN, signature, url, req.body || {});
    if (!valid) return makeError(res, req, 403, 'invalid_signature', 'Invalid Twilio signature');

    const sid = req.body.CallSid;
    const twilioStatus = req.body.CallStatus;
    const incomingStatus = normalizeStatus(twilioStatus);

    const call = callsRepo.findBySidOrClientCallId(sid, req.body.clientCallId);
    if (!call) return res.status(200).json({ ok: true, requestId: req.requestId });

    if (isTerminal(call.status)) return res.status(200).json({ ok: true, requestId: req.requestId });

    const currentNormalized = normalizeStatus(call.twilioStatus);
    if (currentNormalized === incomingStatus) return res.status(200).json({ ok: true, requestId: req.requestId });

    call.sid = sid || call.sid;
    call.twilioStatus = twilioStatus || call.twilioStatus;
    call.status = normalizeStatus(call.twilioStatus);
    call.updated_at = new Date().toISOString();
    if (isTerminal(call.status)) call.ended_at = call.ended_at || new Date().toISOString();

    logger.info({ event: 'voice_call_status_update', requestId: req.requestId, callId: call.id, status: call.status });

    return res.status(200).json({ ok: true, requestId: req.requestId });
  });

  app.post('/api/twilio/status', (req, res) => {
    const sid = req.body?.CallSid;
    const call = callsRepo.findBySidOrClientCallId(sid, req.body?.clientCallId);

    if (call) {
      const mapped = normalizeStatus(req.body?.CallStatus);
      call.sid = sid || call.sid;
      call.twilioStatus = req.body?.CallStatus || call.twilioStatus;
      call.status = mapped;
      call.updated_at = new Date().toISOString();
      if (isTerminal(call.status)) call.ended_at = call.ended_at || new Date().toISOString();
    }

    return res.sendStatus(200);
  });

  app.all('/api/twilio/voice', (_req, res) => {
    res.set('Content-Type', 'text/xml');
    return res.status(200).send('<Response><Dial><Client>agent</Client></Dial></Response>');
  });

  app.post('/api/voice/record/start', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const { callSid, consentState } = req.body || {};
    if (!callSid) return makeError(res, req, 400, 'bad_request', 'callSid is required');

    const record = {
      callSid,
      recordingSid: `RE${crypto.randomUUID().replace(/-/g, '').slice(0, 30)}`,
      status: 'recording',
      encryptionAtRest: true,
      retentionPolicyDays: Number(env.RECORDING_RETENTION_DAYS || 30),
      consentState: consentState || 'unknown',
      startedAt: new Date().toISOString(),
      stoppedAt: null,
      silo: req.headers['x-silo'] || 'bf',
    };

    recordingsByCallSid.set(callSid, record);
    logger.info({ event: 'voice_recording_started', callSid, requestId: req.requestId, silo: record.silo });

    return res.status(200).json({ recording: record, requestId: req.requestId });
  });

  app.post('/api/voice/record/stop', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const { callSid } = req.body || {};
    if (!callSid) return makeError(res, req, 400, 'bad_request', 'callSid is required');

    const existing = recordingsByCallSid.get(callSid);
    if (!existing) return makeError(res, req, 404, 'not_found', 'Recording not found');

    existing.status = 'stopped';
    existing.stoppedAt = new Date().toISOString();

    logger.info({ event: 'voice_recording_stopped', callSid, requestId: req.requestId, silo: existing.silo });

    return res.status(200).json({ recording: existing, requestId: req.requestId });
  });

  app.use((req, res) => makeError(res, req, 404, 'not_found', 'Route not found'));
  app.use((err, req, res, _next) => {
    return makeError(res, req, 500, 'internal_error', 'Unexpected error');
  });

  return app;
}

function createServer(env = process.env, deps = {}) {
  const app = createApp(env, deps);
  const pool = deps.pool || { end: async () => {} };
  const server = http.createServer(app);

  let shuttingDown = false;
  const shutdown = async () => {
    if (shuttingDown) return;
    shuttingDown = true;
    await Promise.race([
      new Promise((resolve) => server.close(() => resolve())),
      new Promise((resolve) => setTimeout(resolve, 5000)),
    ]);
    await pool.end();
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  return { app, server, shutdown };
}

module.exports = { createApp, createServer, STATUS_MAP, normalizeStatus, isTerminal };
