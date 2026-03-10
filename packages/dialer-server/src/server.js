const express = require('express');
const crypto = require('crypto');
const http = require('http');
const cors = require('cors');
const createVoiceRouter = require('./modules/voice/voice.routes');
const { validateTwilioSignature } = require('./modules/voice/twilioWebhookGuard');
const { authMiddleware } = require('./middleware/auth');
const { voiceRateLimit } = require('./middleware/rateLimit');
const { getRedisClient } = require('./infrastructure/redisClient');
const { logger } = require('./infrastructure/logger');
const { createCallsRepo } = require('./repositories/callsRepo');
const { createPresenceRepo } = require('./repositories/presenceRepo');
const { createVoiceSessionsRepo } = require('./repositories/voiceSessionsRepo');
const { createDialerLogRepo } = require('./repositories/dialerLogRepo');
const { startSessionCleanup } = require('./jobs/sessionCleanup');

const STATUS_MAP = { initiated: 'initiated', ringing: 'ringing', answered: 'answered', completed: 'completed', 'in-progress': 'active', failed: 'failed', busy: 'failed', 'no-answer': 'missed', canceled: 'failed' };
const TERMINAL_STATUSES = new Set(['completed', 'failed', 'missed', 'voicemail']);
const WEBHOOK_PATHS = new Set(['/api/voice/status', '/api/voice/recording']);

function normalizeStatus(rawStatus) { return !rawStatus ? 'unknown' : STATUS_MAP[String(rawStatus).toLowerCase()] || 'unknown'; }
function isTerminal(status) { return TERMINAL_STATUSES.has(status); }
function toIdentity(_role, userId) { return String(userId); }
function makeError(res, req, status, code, message) { return res.status(status).json({ code, message, requestId: req.requestId }); }

async function defaultTwilioStartCall(call) { return { sid: `CA${call.id.replace(/-/g, '').slice(0, 30)}` }; }
async function defaultRingStaffLeg({ sessionId, staffId }) { return { sid: `CA${sessionId.replace(/-/g, '').slice(0, 20)}${staffId}`.slice(0, 34) }; }
async function defaultCancelRing() { return true; }
async function defaultRouteVoicemail({ sessionId }) { return { voicemailUrl: `https://recordings.example.com/${sessionId}.mp3` }; }

function createApp(env = process.env, deps = {}) {
  const app = express();
  app.locals.env = env;
  app.use(express.json());
  app.use(express.urlencoded({ extended: false }));
  app.use(cors({
    origin: (origin, cb) => {
      const allowed = String(env.ALLOWED_ORIGINS || '').split(',').map((x) => x.trim()).filter(Boolean);
      if (!origin || allowed.includes(origin)) return cb(null, true);
      return cb(new Error('Not allowed by CORS'));
    },
  }));
  app.use('/api/voice', voiceRateLimit);

  const redis = deps.redis || getRedisClient(env.REDIS_URL);
  const callsRepo = deps.callsRepo || createCallsRepo(redis);
  const voiceSessionsRepo = deps.voiceSessionsRepo || createVoiceSessionsRepo(redis);
  const presenceRepo = deps.presenceRepo || createPresenceRepo(redis);
  const dialerLogRepo = deps.dialerLogRepo || createDialerLogRepo(redis);
  const findAssignedStaffId = deps.findAssignedStaffId || (async () => null);
  const startTwilioCall = deps.startTwilioCall || defaultTwilioStartCall;
  const ringStaffLeg = deps.ringStaffLeg || defaultRingStaffLeg;
  const cancelRingLeg = deps.cancelRingLeg || defaultCancelRing;
  const routeToVoicemail = deps.routeToVoicemail || defaultRouteVoicemail;
  const log = deps.logger || logger;
  const sessionTimers = new Map();
  const voiceEnabled = env.VOICE_ENABLED !== 'false';

  app.use((req, res, next) => { req.requestId = req.headers['x-request-id'] || crypto.randomUUID(); res.setHeader('x-request-id', req.requestId); next(); });
  app.use((req, res, next) => WEBHOOK_PATHS.has(req.path) ? next() : authMiddleware(req, res, next));

  const requireStaff = (req, res, next) => ['staff', 'admin'].includes(String(req.user.role || '').toLowerCase()) ? next() : makeError(res, req, 403, 'forbidden', 'forbidden');
  const requireVoiceTokenRole = (req, res, next) => ['staff', 'admin', 'client'].includes(String(req.user.role || '').toLowerCase()) ? next() : makeError(res, req, 403, 'forbidden', 'forbidden');
  const requireVoiceEnabled = (req, res, next) => voiceEnabled ? next() : makeError(res, req, 503, 'voice_unavailable', 'Voice service is disabled');

  function clearSessionTimers(sessionId) { const timers = sessionTimers.get(sessionId); if (!timers) return; if (timers.assignedOnlyTimeout) clearTimeout(timers.assignedOnlyTimeout); if (timers.voicemailTimeout) clearTimeout(timers.voicemailTimeout); sessionTimers.delete(sessionId); }

  async function ringStaffList(session, staffIds) {
    for (const staffId of staffIds) {
      const exists = session.ringLegs.some((leg) => leg.staffId === staffId && !leg.terminal);
      if (exists) continue;
      const result = await ringStaffLeg({ sessionId: session.id, staffId, clientId: session.clientId, fromIdentity: session.fromIdentity, toIdentity: `staff:${staffId}` });
      if (!result?.sid) continue;
      session.ringLegs.push({ sid: result.sid, staffId, status: 'ringing', terminal: false });
      await voiceSessionsRepo.bindRingSid(session.id, result.sid, staffId);
    }
    session.status = 'ringing';
    await voiceSessionsRepo.save(session);
  }

  async function completeSessionWithVoicemail(session) {
    if (isTerminal(session.status) || session.status === 'answered') return;
    const voicemail = await routeToVoicemail({ sessionId: session.id, clientId: session.clientId, assignedStaffId: session.assignedStaffId });
    session.status = 'voicemail'; session.voicemailUrl = voicemail?.voicemailUrl || null; session.endedAt = new Date().toISOString();
    for (const leg of session.ringLegs) if (!leg.terminal) { await cancelRingLeg({ sid: leg.sid }); leg.terminal = true; leg.status = 'canceled'; }
    clearSessionTimers(session.id);
    await voiceSessionsRepo.save(session);
  }

  app.use('/api/voice', createVoiceRouter({ env, requireVoiceEnabled, makeError, voiceSessionsRepo, findAssignedStaffId }));

  app.post('/api/voice/token', requireVoiceTokenRole, requireVoiceEnabled, async (req, res) => {
    const twilioModule = await import('twilio'); const twilio = twilioModule.default || twilioModule;
    const identity = toIdentity(req.user.role, req.user.id);
    const token = new twilio.jwt.AccessToken(env.TWILIO_ACCOUNT_SID, env.TWILIO_API_KEY, env.TWILIO_API_SECRET, { identity });
    token.addGrant(new twilio.jwt.AccessToken.VoiceGrant({ outgoingApplicationSid: env.TWILIO_VOICE_APP_SID || env.TWILIO_TWIML_APP_SID }));
    res.status(200).json({ token: token.toJwt(), identity, requestId: req.requestId });
  });

  app.post('/api/voice/presence/heartbeat', requireStaff, requireVoiceEnabled, async (req, res) => {
    const { source, status } = req.body || {};
    if (!['portal', 'dialer'].includes(source)) return makeError(res, req, 400, 'bad_request', 'invalid source');
    if (!['online', 'busy', 'offline'].includes(status)) return makeError(res, req, 400, 'bad_request', 'invalid status');
    const record = await presenceRepo.upsert({ staffId: req.user.id, source, status });
    return res.status(200).json({ presence: record, requestId: req.requestId });
  });

  app.post('/api/voice/call', requireStaff, requireVoiceEnabled, async (req, res) => {
    const { fromIdentity, toClientId } = req.body || {};
    if (!fromIdentity || !toClientId) return makeError(res, req, 400, 'bad_request', 'fromIdentity and toClientId are required');
    const assignedStaffId = await findAssignedStaffId(toClientId);
    const session = await voiceSessionsRepo.create({ clientId: toClientId, assignedStaffId, fromIdentity });
    const onlineStaff = await presenceRepo.listEligibleStaff();
    if (assignedStaffId && onlineStaff.includes(assignedStaffId)) {
      await ringStaffList(session, [assignedStaffId]);
      const assignedOnlyTimeout = setTimeout(async () => { const fresh = await voiceSessionsRepo.getById(session.id); if (!fresh || fresh.status === 'answered' || isTerminal(fresh.status)) return; await ringStaffList(fresh, await presenceRepo.listEligibleStaff()); }, 10000);
      const voicemailTimeout = setTimeout(async () => { const fresh = await voiceSessionsRepo.getById(session.id); if (fresh) await completeSessionWithVoicemail(fresh); }, 25000);
      sessionTimers.set(session.id, { assignedOnlyTimeout, voicemailTimeout });
    } else {
      await ringStaffList(session, onlineStaff);
      const voicemailTimeout = setTimeout(async () => { const fresh = await voiceSessionsRepo.getById(session.id); if (fresh) await completeSessionWithVoicemail(fresh); }, 25000);
      sessionTimers.set(session.id, { voicemailTimeout });
    }
    res.status(200).json({ callSession: session, requestId: req.requestId });
  });

  app.post('/api/voice/calls/start', requireStaff, requireVoiceEnabled, async (req, res) => {
    const { clientCallId, to, applicationId } = req.body || {};
    if (!to || (!clientCallId && !applicationId)) return makeError(res, req, 400, 'bad_request', 'missing call identifiers');
    let call = applicationId ? await callsRepo.findActiveCall(req.user.id, applicationId) : null;
    if (!call) call = await callsRepo.upsertCallAtomic({ userId: req.user.id, clientCallId, to, applicationId });
    try {
      const twilioResult = await Promise.race([startTwilioCall(call, env), new Promise((_, r) => setTimeout(() => r(new Error('twilio_timeout')), 4000))]);
      if (twilioResult?.sid) call.sid = twilioResult.sid;
      call.updated_at = new Date().toISOString();
      if (normalizeStatus(call.twilioStatus) !== 'unknown') call.status = normalizeStatus(call.twilioStatus);
      await callsRepo.save(call);
      log.info({ event: 'voice_call_started', callSid: call.sid, staffId: req.user.id, sessionId: call.id });
      return res.status(200).json({ call: { ...call, status: call.status }, requestId: req.requestId });
    } catch {
      call.status = 'failed'; call.ended_at = call.ended_at || new Date().toISOString(); call.updated_at = new Date().toISOString(); await callsRepo.save(call);
      return makeError(res, req, 504, 'upstream_timeout', 'Twilio call start timed out');
    }
  });

  app.post('/api/voice/calls/end', requireStaff, requireVoiceEnabled, async (req, res) => {
    const call = await callsRepo.getById((req.body || {}).id);
    if (!call) return makeError(res, req, 404, 'not_found', 'Call not found');
    if (call.user_id !== req.user.id) return makeError(res, req, 403, 'forbidden', 'Call ownership violation');
    if (!isTerminal(call.status)) { call.status = 'completed'; call.ended_at = call.ended_at || new Date().toISOString(); call.updated_at = new Date().toISOString(); await callsRepo.save(call); }
    return res.status(200).json({ call, requestId: req.requestId });
  });

  app.get('/api/voice/calls/:id', requireStaff, requireVoiceEnabled, async (req, res) => {
    const call = await callsRepo.getById(req.params.id);
    if (!call) return makeError(res, req, 404, 'not_found', 'Call not found');
    if (call.user_id !== req.user.id) return makeError(res, req, 403, 'forbidden', 'Call ownership violation');
    return res.status(200).json({ call: { id: call.id, clientCallId: call.clientCallId, status: call.status, started_at: call.started_at, ended_at: call.ended_at }, requestId: req.requestId });
  });

  app.post('/api/voice/status', validateTwilioSignature, async (req, res) => {
    const sid = req.body.CallSid; const twilioStatus = req.body.CallStatus;
    const ringLookup = sid ? await voiceSessionsRepo.lookupByRingSid(sid) : null;
    if (ringLookup) {
      const session = await voiceSessionsRepo.getById(ringLookup.sessionId);
      if (session) {
        const leg = session.ringLegs.find((ringLeg) => ringLeg.sid === sid);
        if (leg) { leg.status = String(twilioStatus || leg.status).toLowerCase(); if (['completed', 'busy', 'failed', 'no-answer', 'canceled'].includes(leg.status)) leg.terminal = true; }
        if (String(twilioStatus).toLowerCase() === 'answered' && session.status !== 'answered') {
          session.status = 'answered'; session.answeredByStaffId = ringLookup.staffId; session.answeredAt = new Date().toISOString(); clearSessionTimers(session.id);
          for (const other of session.ringLegs) if (other.sid !== sid && !other.terminal) { await cancelRingLeg({ sid: other.sid }); other.terminal = true; other.status = 'canceled'; }
        }
        if (['completed', 'failed', 'busy', 'no-answer'].includes(String(twilioStatus).toLowerCase()) && session.status === 'answered') { session.status = 'completed'; session.endedAt = session.endedAt || new Date().toISOString(); }
        await voiceSessionsRepo.save(session);
      }
    }

    const call = await callsRepo.findBySidOrClientCallId(sid, req.body.clientCallId);
    if (!call || isTerminal(call.status) || normalizeStatus(call.twilioStatus) === normalizeStatus(twilioStatus)) return res.status(200).json({ ok: true, requestId: req.requestId });
    call.sid = sid || call.sid; call.twilioStatus = twilioStatus || call.twilioStatus; call.status = normalizeStatus(call.twilioStatus); call.updated_at = new Date().toISOString(); if (isTerminal(call.status)) call.ended_at = call.ended_at || new Date().toISOString();
    await callsRepo.save(call);
    log.info({ event: 'voice_call_status_update', callSid: sid, staffId: call.user_id, sessionId: call.id });
    return res.status(200).json({ ok: true, requestId: req.requestId });
  });

  app.post('/api/voice/recording', validateTwilioSignature, async (req, res) => {
    const { RecordingSid, RecordingUrl, RecordingDuration, CallSid } = req.body || {};
    const call = await callsRepo.findBySidOrClientCallId(CallSid, null);
    if (call) { call.recording_sid = RecordingSid || call.recording_sid; call.recording_url = RecordingUrl || call.recording_url; call.recording_duration = Number(RecordingDuration); call.updated_at = new Date().toISOString(); await callsRepo.save(call); }
    return res.sendStatus(200);
  });

  app.use((req, res) => makeError(res, req, 404, 'not_found', 'Route not found'));
  app.use((_err, req, res, _next) => makeError(res, req, 500, 'internal_error', 'Unexpected error'));

  app.locals.cleanupStop = startSessionCleanup({ voiceSessionsRepo, presenceRepo, dialerLogRepo, logger: log });
  return app;
}

function createServer(env = process.env, deps = {}) {
  const app = createApp(env, deps);
  const server = http.createServer(app);
  let shuttingDown = false;
  const shutdown = async () => { if (shuttingDown) return; shuttingDown = true; if (app.locals.cleanupStop) app.locals.cleanupStop(); await new Promise((resolve) => server.close(() => resolve())); };
  process.on('SIGTERM', shutdown); process.on('SIGINT', shutdown);
  return { app, server, shutdown };
}

module.exports = { createApp, createServer, STATUS_MAP, normalizeStatus, isTerminal, toIdentity };
