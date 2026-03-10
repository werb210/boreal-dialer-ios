import crypto from 'crypto';

const CALL_PREFIX = 'dialer:call:';
const CALL_CLIENT_INDEX = 'dialer:call:clientKey';
const CALL_APP_INDEX = 'dialer:call:applicationKey';
const CALL_SID_INDEX = 'dialer:call:sid';
const CALL_CLIENT_GLOBAL_INDEX = 'dialer:call:clientGlobal';

function createCallsRepo(redis) {
  return {
    async upsertCallAtomic({ userId, clientCallId, to, applicationId }) {
      const dedupeKey = `${userId}:${clientCallId}`;
      const existingId = clientCallId ? await redis.hget(CALL_CLIENT_INDEX, dedupeKey) : null;
      if (existingId) {
        const existing = await this.getById(existingId);
        if (existing) {
          existing.updated_at = new Date().toISOString();
          await this.save(existing);
          return existing;
        }
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
      const tx = redis.multi().set(`${CALL_PREFIX}${id}`, JSON.stringify(call));
      if (clientCallId) { tx.hset(CALL_CLIENT_INDEX, dedupeKey, id); tx.hset(CALL_CLIENT_GLOBAL_INDEX, clientCallId, id); }
      if (applicationId) tx.hset(CALL_APP_INDEX, `${userId}:${applicationId}`, id);
      await tx.exec();
      return call;
    },
    async save(call) {
      const tx = redis.multi().set(`${CALL_PREFIX}${call.id}`, JSON.stringify(call));
      if (call.sid) tx.hset(CALL_SID_INDEX, call.sid, call.id);
      await tx.exec();
      return call;
    },
    async findActiveCall(userId, applicationId) {
      const id = await redis.hget(CALL_APP_INDEX, `${userId}:${applicationId}`);
      if (!id) return null;
      return this.getById(id);
    },
    async getById(id) {
      const raw = await redis.get(`${CALL_PREFIX}${id}`);
      return raw ? JSON.parse(raw) : null;
    },
    async findBySidOrClientCallId(sid, clientCallId, userId = null) {
      if (sid) {
        const id = await redis.hget(CALL_SID_INDEX, sid);
        if (id) return this.getById(id);
      }
      if (clientCallId && userId) {
        const id = await redis.hget(CALL_CLIENT_INDEX, `${userId}:${clientCallId}`);
        if (id) return this.getById(id);
      }
      if (clientCallId) {
        const id = await redis.hget(CALL_CLIENT_GLOBAL_INDEX, clientCallId);
        if (id) return this.getById(id);
      }
      return null;
    },
  };
}

export { createCallsRepo };
