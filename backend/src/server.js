const express = require('express');
const crypto = require('crypto');
const http = require('http');
const createVoiceRouter = require('./modules/voice/voice.routes');
const { updatePresence } = require('./modules/voice/presence');
const { validateTwilioSignature } = require('./modules/voice/twilioWebhookGuard');

const STATUS_MAP = {
  initiated: 'initiated',
  ringing: 'ringing',
  answered: 'answered',
  completed: 'completed',
  'in-progress': 'active',
  failed: 'failed',
  busy: 'failed',
  'no-answer': 'missed',
  canceled: 'failed',
};

const TERMINAL_STATUSES = new Set(['completed', 'failed', 'missed', 'voicemail']);

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

function toIdentity(role, userId) {
  const normalizedRole = String(role || '').toLowerCase();
  if (normalizedRole === 'client') return `client:${userId}`;
  return `staff:${userId}`;
}

function createInMemoryCallsRepo() {
  const callsById = new Map();
  const callsByClientKey = new Map();
  const callsByApplicationKey = new Map();

  return {
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
        recording_sid: null,
        recording_url: null,
        recording_duration: null,
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
      if (!call || isTerminal(call.status)) return null;
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


function createInMemoryDialerLogRepo() {
  const entries = [];

  return {
    create(entry) {
      const record = {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        ...entry,
      };
      entries.push(record);
      return record;
    },
    list() {
      return [...entries];
    },
  };
}

function createInMemoryVoiceSessionRepo() {
  const sessions = new Map();
  const ringSidToSession = new Map();

  return {
    create({ clientId, assignedStaffId, fromIdentity }) {
      const now = new Date().toISOString();
      const id = crypto.randomUUID();
      const session = {
        id,
        clientId,
        assignedStaffId,
        answeredByStaffId: null,
        status: 'initiated',
        fromIdentity,
        startedAt: now,
        answeredAt: null,
        endedAt: null,
        voicemailUrl: null,
        ringLegs: [],
      };
      sessions.set(id, session);
      return session;
    },
    getById(id) {
      return sessions.get(id) || null;
    },
    save(session) {
      sessions.set(session.id, session);
      return session;
    },
    bindRingSid(sessionId, sid, staffId) {
      ringSidToSession.set(sid, { sessionId, staffId });
    },
    lookupByRingSid(sid) {
      return ringSidToSession.get(sid) || null;
    },
  };
}

function createInMemoryPresenceRepo() {
  const entries = new Map();

  const isStale = (record) => Date.now() - new Date(record.lastSeen).getTime() > 30000;

  return {
    upsert({ staffId, source, status }) {
      const key = `${staffId}:${source}`;
      const record = {
        staffId,
        source,
        status,
        lastSeen: new Date().toISOString(),
      };
      entries.set(key, record);
      return record;
    },
    listEligibleStaff() {
      const byStaff = new Map();
      for (const record of entries.values()) {
        if (isStale(record)) continue;
        if (!byStaff.has(record.staffId)) {
          byStaff.set(record.staffId, []);
        }
        byStaff.get(record.staffId).push(record);
      }

      const eligible = [];
      for (const [staffId, sources] of byStaff.entries()) {
        const hasOnline = sources.some((sourceRecord) => sourceRecord.status === 'online');
        const hasBusy = sources.some((sourceRecord) => sourceRecord.status === 'busy');
        if (hasOnline && !hasBusy) eligible.push(staffId);
      }
      return eligible;
    },
  };
}

async function defaultTwilioStartCall(call, env) {
  if (env.MOCK_TWILIO_DELAY_MS) {
    await new Promise((resolve) => setTimeout(resolve, Number(env.MOCK_TWILIO_DELAY_MS)));
  }
  return { sid: `CA${call.id.replace(/-/g, '').slice(0, 30)}` };
}

async function defaultRingStaffLeg({ sessionId, staffId }) {
  return { sid: `CA${sessionId.replace(/-/g, '').slice(0, 20)}${staffId}`.slice(0, 34) };
}

async function defaultCancelRing() {
  return true;
}

async function defaultRouteVoicemail({ sessionId }) {
  return {
    voicemailUrl: `https://recordings.example.com/${sessionId}.mp3`,
  };
}

function createApp(env = process.env, deps = {}) {
  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: false }));
  app.locals.env = env;

  const callsRepo = deps.callsRepo || createInMemoryCallsRepo();
  const voiceSessionsRepo = deps.voiceSessionsRepo || createInMemoryVoiceSessionRepo();
  const presenceRepo = deps.presenceRepo || createInMemoryPresenceRepo();
  const dialerLogRepo = deps.dialerLogRepo || createInMemoryDialerLogRepo();
  const findAssignedStaffId = deps.findAssignedStaffId || (async () => null);

  const startTwilioCall = deps.startTwilioCall || defaultTwilioStartCall;
  const ringStaffLeg = deps.ringStaffLeg || defaultRingStaffLeg;
  const cancelRingLeg = deps.cancelRingLeg || defaultCancelRing;
  const routeToVoicemail = deps.routeToVoicemail || defaultRouteVoicemail;

  const logger = deps.logger || console;
  const recordingsByCallSid = new Map();
  const sessionTimers = new Map();

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

  function requireVoiceTokenRole(req, res, next) {
    const role = String(req.user.role || '').toLowerCase();
    if (!['staff', 'admin', 'client'].includes(role)) {
      return makeError(res, req, 403, 'forbidden', 'forbidden');
    }
    return next();
  }

  function requireVoiceEnabled(req, res, next) {
    if (!voiceEnabled) return makeError(res, req, 503, 'voice_unavailable', 'Voice service is disabled');
    return next();
  }

  function clearSessionTimers(sessionId) {
    const timers = sessionTimers.get(sessionId);
    if (!timers) return;
    if (timers.assignedOnlyTimeout) clearTimeout(timers.assignedOnlyTimeout);
    if (timers.voicemailTimeout) clearTimeout(timers.voicemailTimeout);
    sessionTimers.delete(sessionId);
  }

  async function ringStaffList(session, staffIds) {
    for (const staffId of staffIds) {
      const exists = session.ringLegs.some((leg) => leg.staffId === staffId && !leg.terminal);
      if (exists) continue;
      const result = await ringStaffLeg({
        sessionId: session.id,
        staffId,
        clientId: session.clientId,
        fromIdentity: session.fromIdentity,
        toIdentity: `staff:${staffId}`,
      });
      if (!result?.sid) continue;
      const leg = { sid: result.sid, staffId, status: 'ringing', terminal: false };
      session.ringLegs.push(leg);
      voiceSessionsRepo.bindRingSid(session.id, result.sid, staffId);
    }
    session.status = 'ringing';
    voiceSessionsRepo.save(session);
  }

  async function completeSessionWithVoicemail(session) {
    if (isTerminal(session.status) || session.status === 'answered') return;
    const voicemail = await routeToVoicemail({ sessionId: session.id, clientId: session.clientId, assignedStaffId: session.assignedStaffId });
    session.status = 'voicemail';
    session.voicemailUrl = voicemail?.voicemailUrl || null;
    session.endedAt = new Date().toISOString();
    for (const leg of session.ringLegs) {
      if (!leg.terminal) {
        await cancelRingLeg({ sid: leg.sid });
        leg.terminal = true;
        leg.status = 'canceled';
      }
    }
    clearSessionTimers(session.id);
    voiceSessionsRepo.save(session);
  }

  app.use('/api/voice', createVoiceRouter({
    env,
    requireAuth,
    requireVoiceEnabled,
    makeError,
    voiceSessionsRepo,
    findAssignedStaffId,
  }));

  app.get('/api/voice/token', requireAuth, requireVoiceTokenRole, requireVoiceEnabled, async (req, res) => {
    const twilioModule = await import('twilio');
    const twilio = twilioModule.default || twilioModule;
    const identity = toIdentity(req.user.role, req.user.id);
    const token = new twilio.jwt.AccessToken(env.TWILIO_ACCOUNT_SID, env.TWILIO_API_KEY, env.TWILIO_API_SECRET, { identity });
    token.addGrant(new twilio.jwt.AccessToken.VoiceGrant({ outgoingApplicationSid: env.TWILIO_VOICE_APP_SID || env.TWILIO_TWIML_APP_SID }));
    res.status(200).json({ token: token.toJwt(), identity, requestId: req.requestId });
  });

  app.post('/api/voice/token', requireAuth, requireVoiceTokenRole, requireVoiceEnabled, async (req, res) => {
    const twilioModule = await import('twilio');
    const twilio = twilioModule.default || twilioModule;
    const identity = toIdentity(req.user.role, req.user.id);
    const token = new twilio.jwt.AccessToken(env.TWILIO_ACCOUNT_SID, env.TWILIO_API_KEY, env.TWILIO_API_SECRET, { identity });
    token.addGrant(new twilio.jwt.AccessToken.VoiceGrant({ outgoingApplicationSid: env.TWILIO_VOICE_APP_SID || env.TWILIO_TWIML_APP_SID }));
    res.status(200).json({ token: token.toJwt(), identity, requestId: req.requestId });
  });


  app.post('/api/dialer/log', requireAuth, requireVoiceEnabled, (req, res) => {
    const { direction, to, from, callSid } = req.body || {};
    if (!direction || !to || !from || !callSid) {
      return makeError(res, req, 400, 'bad_request', 'direction, to, from, and callSid are required');
    }

    const record = dialerLogRepo.create({
      userId: req.user.id,
      direction,
      to,
      from,
      callSid,
    });

    return res.status(201).json({ log: record, requestId: req.requestId });
  });

  app.post('/api/voice/presence/heartbeat', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const source = req.body?.source;
    const status = req.body?.status;
    if (!['portal', 'dialer'].includes(source)) return makeError(res, req, 400, 'bad_request', 'invalid source');
    if (!['online', 'busy', 'offline'].includes(status)) return makeError(res, req, 400, 'bad_request', 'invalid status');

    const record = presenceRepo.upsert({ staffId: req.user.id, source, status });
    updatePresence({ staffId: req.user.id, source, status, lastSeen: Date.now() });
    return res.status(200).json({ presence: record, requestId: req.requestId });
  });

  app.post('/api/voice/presence', requireAuth, requireStaff, requireVoiceEnabled, (req, res) => {
    const source = req.body?.source;
    const status = req.body?.status;
    if (!['portal', 'dialer'].includes(source)) return makeError(res, req, 400, 'bad_request', 'invalid source');
    if (!['online', 'busy'].includes(status)) return makeError(res, req, 400, 'bad_request', 'invalid status');
    updatePresence({ staffId: req.user.id, source, status, lastSeen: Date.now() });
    return res.status(204).send();
  });

  app.post('/api/voice/call', requireAuth, requireStaff, requireVoiceEnabled, async (req, res) => {
    const { fromIdentity, toClientId } = req.body || {};
    if (!fromIdentity || !toClientId) return makeError(res, req, 400, 'bad_request', 'fromIdentity and toClientId are required');

    const assignedStaffId = await findAssignedStaffId(toClientId);
    const session = voiceSessionsRepo.create({
      clientId: toClientId,
      assignedStaffId,
      fromIdentity,
    });

    const onlineStaff = presenceRepo.listEligibleStaff();

    if (assignedStaffId && onlineStaff.includes(assignedStaffId)) {
      await ringStaffList(session, [assignedStaffId]);
      const assignedOnlyTimeout = setTimeout(async () => {
        const fresh = voiceSessionsRepo.getById(session.id);
        if (!fresh || fresh.status === 'answered' || isTerminal(fresh.status)) return;
        const fallbackStaff = presenceRepo.listEligibleStaff();
        await ringStaffList(fresh, fallbackStaff);
      }, 10000);
      const voicemailTimeout = setTimeout(async () => {
        const fresh = voiceSessionsRepo.getById(session.id);
        if (!fresh) return;
        await completeSessionWithVoicemail(fresh);
      }, 25000);
      sessionTimers.set(session.id, { assignedOnlyTimeout, voicemailTimeout });
    } else {
      await ringStaffList(session, onlineStaff);
      const voicemailTimeout = setTimeout(async () => {
        const fresh = voiceSessionsRepo.getById(session.id);
        if (!fresh) return;
        await completeSessionWithVoicemail(fresh);
      }, 25000);
      sessionTimers.set(session.id, { voicemailTimeout });
    }

    return res.status(200).json({ callSession: session, requestId: req.requestId });
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

  app.post('/api/voice/status', validateTwilioSignature, async (req, res) => {
    const sid = req.body.CallSid;
    const twilioStatus = req.body.CallStatus;

    const ringLookup = sid ? voiceSessionsRepo.lookupByRingSid(sid) : null;
    if (ringLookup) {
      const session = voiceSessionsRepo.getById(ringLookup.sessionId);
      if (!session) return res.status(200).json({ ok: true, requestId: req.requestId });

      const leg = session.ringLegs.find((ringLeg) => ringLeg.sid === sid);
      if (leg) {
        leg.status = String(twilioStatus || leg.status).toLowerCase();
        if (['completed', 'busy', 'failed', 'no-answer', 'canceled'].includes(leg.status)) {
          leg.terminal = true;
        }
      }

      if (String(twilioStatus).toLowerCase() === 'answered' && session.status !== 'answered') {
        session.status = 'answered';
        session.answeredByStaffId = ringLookup.staffId;
        session.answeredAt = new Date().toISOString();
        clearSessionTimers(session.id);

        for (const other of session.ringLegs) {
          if (other.sid !== sid && !other.terminal) {
            cancelRingLeg({ sid: other.sid });
            other.terminal = true;
            other.status = 'canceled';
          }
        }
      }

      if (['completed', 'failed', 'busy', 'no-answer'].includes(String(twilioStatus).toLowerCase()) && session.status === 'answered') {
        session.status = 'completed';
        session.endedAt = session.endedAt || new Date().toISOString();
      }

      voiceSessionsRepo.save(session);
    }

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


  app.post('/api/voice/recording', validateTwilioSignature, async (req, res) => {
    const { RecordingSid, RecordingUrl, RecordingDuration, CallSid } = req.body || {};

    try {
      const call = callsRepo.findBySidOrClientCallId(CallSid, null);
      if (call) {
        call.recording_sid = RecordingSid || call.recording_sid;
        call.recording_url = RecordingUrl || call.recording_url;
        call.recording_duration = Number(RecordingDuration);
        call.updated_at = new Date().toISOString();
      }
      return res.sendStatus(200);
    } catch {
      return res.sendStatus(500);
    }
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

module.exports = { createApp, createServer, STATUS_MAP, normalizeStatus, isTerminal, toIdentity };
