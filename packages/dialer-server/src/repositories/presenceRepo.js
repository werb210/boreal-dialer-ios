const PRESENCE_PREFIX = 'dialer:presence:';
const PRESENCE_INDEX = 'dialer:presence:index';
const PRESENCE_TTL_SECONDS = 30;

function createPresenceRepo(redis) {
  return {
    async upsert({ staffId, source, status }) {
      const key = `${PRESENCE_PREFIX}${staffId}`;
      const record = {
        staffId,
        source,
        status,
        updatedAt: Date.now(),
      };
      await redis.multi().set(key, JSON.stringify(record), 'EX', PRESENCE_TTL_SECONDS).sadd(PRESENCE_INDEX, staffId).exec();
      return record;
    },
    async listEligibleStaff() {
      const staffIds = await redis.smembers(PRESENCE_INDEX);
      const eligible = [];
      for (const staffId of staffIds) {
        const raw = await redis.get(`${PRESENCE_PREFIX}${staffId}`);
        if (!raw) continue;
        const record = JSON.parse(raw);
        if (record.status === 'online') eligible.push(staffId);
      }
      return eligible;
    },
    async removeStale() {
      const staffIds = await redis.smembers(PRESENCE_INDEX);
      for (const staffId of staffIds) {
        const exists = await redis.exists(`${PRESENCE_PREFIX}${staffId}`);
        if (!exists) await redis.srem(PRESENCE_INDEX, staffId);
      }
    },
  };
}

export { createPresenceRepo };
