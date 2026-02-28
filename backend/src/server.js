const express = require('express');
const crypto = require('crypto');
const twilio = require('twilio');

const lifecycleMap = {
  queued: 'ringing',
  ringing: 'ringing',
  'in-progress': 'active',
  completed: 'completed',
  busy: 'failed',
  'no-answer': 'failed',
};

function makeError(res, req, status, code, message) {
  return res.status(status).json({ code, message, requestId: req.requestId });
}

function createApp(env = process.env) {
  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: false }));

  const callsById = new Map();
  const callsByClientKey = new Map();

  const voiceEnabled = Boolean(
    env.TWILIO_ACCOUNT_SID &&
    env.TWILIO_AUTH_TOKEN &&
    env.TWILIO_API_KEY &&
    env.TWILIO_API_SECRET &&
    env.TWILIO_TWIML_APP_SID
  );

  app.use((req, _res, next) => {
    req.requestId = req.headers['x-request-id'] || crypto.randomUUID();
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

  function requireRole(req, res, next) {
    if (!['staff', 'admin'].includes((req.user.role || '').toLowerCase())) {
      return makeError(res, req, 403, 'forbidden', 'Insufficient role');
    }
    return next();
  }

  function requireVoiceEnabled(req, res, next) {
    if (!voiceEnabled) return makeError(res, req, 503, 'voice_unavailable', 'Voice service is disabled');
    return next();
  }

  app.post('/api/voice/token', requireAuth, requireRole, requireVoiceEnabled, (req, res) => {
    const token = new twilio.jwt.AccessToken(
      env.TWILIO_ACCOUNT_SID,
      env.TWILIO_API_KEY,
      env.TWILIO_API_SECRET,
      { identity: req.user.id }
    );
    token.addGrant(new twilio.jwt.AccessToken.VoiceGrant({ outgoingApplicationSid: env.TWILIO_TWIML_APP_SID }));

    res.status(200).json({ token: token.toJwt(), identity: req.user.id });
  });

  app.post('/api/voice/calls/start', requireAuth, requireRole, requireVoiceEnabled, (req, res) => {
    const { clientCallId, to } = req.body || {};
    if (!clientCallId || !to) return makeError(res, req, 400, 'bad_request', 'clientCallId and to are required');

    const dedupeKey = `${req.user.id}:${clientCallId}`;
    const existingId = callsByClientKey.get(dedupeKey);
    if (existingId) {
      return res.status(200).json({ call: callsById.get(existingId) });
    }

    const id = crypto.randomUUID();
    const call = {
      id,
      user_id: req.user.id,
      clientCallId,
      to,
      status: 'initiated',
      twilioStatus: null,
      sid: null,
      started_at: new Date().toISOString(),
      ended_at: null,
    };

    callsById.set(id, call);
    callsByClientKey.set(dedupeKey, id);
    return res.status(200).json({ call });
  });

  app.post('/api/voice/calls/end', requireAuth, requireRole, requireVoiceEnabled, (req, res) => {
    const { id } = req.body || {};
    const call = callsById.get(id);
    if (!call) return makeError(res, req, 404, 'not_found', 'Call not found');
    if (call.user_id !== req.user.id) return makeError(res, req, 403, 'forbidden', 'Call ownership violation');

    if (call.status !== 'completed') {
      call.status = 'completed';
      call.ended_at = call.ended_at || new Date().toISOString();
    }
    return res.status(200).json({ call });
  });

  app.get('/api/voice/calls/:id', requireAuth, requireRole, requireVoiceEnabled, (req, res) => {
    const call = callsById.get(req.params.id);
    if (!call) return makeError(res, req, 404, 'not_found', 'Call not found');
    if (call.user_id !== req.user.id) return makeError(res, req, 403, 'forbidden', 'Call ownership violation');

    const normalizedStatus = lifecycleMap[call.twilioStatus] || call.status;
    return res.status(200).json({
      call: {
        id: call.id,
        clientCallId: call.clientCallId,
        status: normalizedStatus,
        started_at: call.started_at,
        ended_at: call.ended_at,
      },
    });
  });

  app.post('/api/voice/status', requireVoiceEnabled, (req, res) => {
    const signature = req.headers['x-twilio-signature'];
    const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
    const valid = twilio.validateRequest(env.TWILIO_AUTH_TOKEN, signature, url, req.body || {});
    if (!valid) return makeError(res, req, 403, 'invalid_signature', 'Invalid Twilio signature');

    const sid = req.body.CallSid;
    const twilioStatus = req.body.CallStatus;

    const call = [...callsById.values()].find((c) => c.sid === sid || c.clientCallId === req.body.clientCallId);
    if (call) {
      call.sid = sid || call.sid;
      call.twilioStatus = twilioStatus || call.twilioStatus;
      call.status = lifecycleMap[call.twilioStatus] || call.status;
      if (call.status === 'completed') call.ended_at = call.ended_at || new Date().toISOString();
    }

    return res.status(200).json({ ok: true, requestId: req.requestId });
  });

  app.use((req, res) => makeError(res, req, 404, 'not_found', 'Route not found'));
  app.use((err, req, res, _next) => {
    return makeError(res, req, 500, 'internal_error', 'Unexpected error');
  });

  return app;
}

module.exports = { createApp, lifecycleMap };
