import crypto from 'crypto';

const SESSION_PREFIX = 'dialer:session:';
const SESSION_INDEX = 'dialer:session:index';
const RING_PREFIX = 'dialer:ring:';

function createVoiceSessionsRepo(redis) {
  return {
    async create({ clientId, assignedStaffId, fromIdentity }) {
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
      await redis.multi().set(`${SESSION_PREFIX}${id}`, JSON.stringify(session)).zadd(SESSION_INDEX, Date.now(), id).exec();
      return session;
    },
    async getById(id) {
      const raw = await redis.get(`${SESSION_PREFIX}${id}`);
      return raw ? JSON.parse(raw) : null;
    },
    async save(session) {
      await redis.multi().set(`${SESSION_PREFIX}${session.id}`, JSON.stringify(session)).zadd(SESSION_INDEX, Date.now(), session.id).exec();
      return session;
    },
    async bindRingSid(sessionId, sid, staffId) {
      await redis.set(`${RING_PREFIX}${sid}`, JSON.stringify({ sessionId, staffId }));
    },
    async lookupByRingSid(sid) {
      const raw = await redis.get(`${RING_PREFIX}${sid}`);
      return raw ? JSON.parse(raw) : null;
    },
    async removeExpiredSessions(maxAgeMs = 24 * 60 * 60 * 1000) {
      const cutoff = Date.now() - maxAgeMs;
      const ids = await redis.zrangebyscore(SESSION_INDEX, 0, cutoff);
      for (const id of ids) {
        await redis.del(`${SESSION_PREFIX}${id}`);
        await redis.zrem(SESSION_INDEX, id);
      }
      return ids.length;
    },
  };
}

export { createVoiceSessionsRepo };
