const express = require('express');
const crypto = require('crypto');
const { updatePresence, getOnlineStaff, markBusy, markAvailable } = require('./presence');

const ROLE_TOKEN_ALLOWED = new Set(['admin', 'staff', 'client']);
const ROLE_STAFF_ALLOWED = new Set(['admin', 'staff']);

const STATUS_MAP = {
  ringing: 'ringing',
  'in-progress': 'connected',
  completed: 'completed',
  'no-answer': 'missed',
};

async function loadTwilio() {
  const mod = await import('twilio');
  return mod.default || mod;
}

function normalizeRole(role) {
  return String(role || '').toLowerCase();
}

function createVoiceRouter(opts) {
  const {
    env,
    requireAuth,
    requireVoiceEnabled,
    makeError,
    voiceSessionsRepo,
    findAssignedStaffId,
  } = opts;

  const router = express.Router();

  router.post('/token', requireAuth, requireVoiceEnabled, async (req, res) => {
    const role = normalizeRole(req.user?.role);
    if (!ROLE_TOKEN_ALLOWED.has(role)) return makeError(res, req, 403, 'forbidden', 'forbidden');

    const identity = role === 'client' ? `client:${req.user.id}` : `staff:${req.user.id}`;
    const twilio = await loadTwilio();
    const token = new twilio.jwt.AccessToken(
      env.TWILIO_ACCOUNT_SID,
      env.TWILIO_API_KEY,
      env.TWILIO_API_SECRET,
      { identity }
    );
    token.addGrant(new twilio.jwt.AccessToken.VoiceGrant({ outgoingApplicationSid: env.TWILIO_VOICE_APP_SID || env.TWILIO_TWIML_APP_SID }));
    return res.status(200).json({ token: token.toJwt(), identity, requestId: req.requestId });
  });

  router.post('/presence', requireAuth, requireVoiceEnabled, (req, res) => {
    const role = normalizeRole(req.user?.role);
    if (!ROLE_STAFF_ALLOWED.has(role)) return makeError(res, req, 403, 'forbidden', 'forbidden');
    const { status, source } = req.body || {};
    if (!['online', 'busy'].includes(status)) return makeError(res, req, 400, 'bad_request', 'invalid status');
    if (!['portal', 'dialer'].includes(source)) return makeError(res, req, 400, 'bad_request', 'invalid source');

    updatePresence({ staffId: req.user.id, status, source, lastSeen: Date.now() });
    return res.status(204).send();
  });

  router.post('/call', requireAuth, requireVoiceEnabled, async (req, res, next) => {
    if (req.body?.fromIdentity || req.body?.toClientId) return next();
    const role = normalizeRole(req.user?.role);
    if (!ROLE_STAFF_ALLOWED.has(role)) return makeError(res, req, 403, 'forbidden', 'forbidden');

    const clientId = req.body?.clientId || req.body?.toClientId;
    if (!clientId) return makeError(res, req, 400, 'bad_request', 'clientId is required');

    const assignedStaffId = (await findAssignedStaffId(clientId)) || req.user.id;
    const callSession = voiceSessionsRepo.create({
      clientId,
      assignedStaffId,
      fromIdentity: `client:${clientId}`,
    });

    const onlineStaff = getOnlineStaff().map((r) => r.staffId);
    const ringTargets = onlineStaff.map((id) => `staff:${id}`);

    return res.status(200).json({
      callId: callSession.id,
      ringTargets,
      callSession,
      requestId: req.requestId,
    });
  });

  router.post('/status', async (req, res, next) => {
    if (!req.body?.callId || !req.body?.callStatus) return next();
    const signature = req.headers['x-twilio-signature'];
    if (!signature) return makeError(res, req, 403, 'invalid_signature', 'Missing Twilio signature');

    const twilio = await loadTwilio();
    const url = `${req.protocol}://${req.get('host')}${req.originalUrl}`;
    const valid = twilio.validateRequest(env.TWILIO_AUTH_TOKEN, signature, url, req.body || {});
    if (!valid) return makeError(res, req, 403, 'invalid_signature', 'Invalid Twilio signature');

    const callId = req.body.callId;
    const callStatus = String(req.body.callStatus || req.body.CallStatus || '').toLowerCase();
    const staffId = req.body.staffId;
    const recordingUrl = req.body.recordingUrl;

    if (!callId) return res.status(200).json({ ok: true, requestId: req.requestId });
    const session = voiceSessionsRepo.getById(callId);
    if (!session) return res.status(200).json({ ok: true, requestId: req.requestId });

    session.status = STATUS_MAP[callStatus] || session.status;
    if (recordingUrl) session.voicemailUrl = recordingUrl;

    if (callStatus === 'in-progress') {
      session.answeredByStaffId = staffId || session.answeredByStaffId;
      session.answeredAt = session.answeredAt || new Date().toISOString();
      if (staffId) markBusy(staffId);
    }
    if (callStatus === 'completed') {
      session.endedAt = session.endedAt || new Date().toISOString();
      if (staffId) markAvailable(staffId);
    }

    voiceSessionsRepo.save(session);
    return res.status(200).json({ ok: true, requestId: req.requestId });
  });

  return router;
}

module.exports = createVoiceRouter;
