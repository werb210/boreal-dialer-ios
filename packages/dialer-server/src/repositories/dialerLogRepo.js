const crypto = require('crypto');

const LOG_PREFIX = 'dialer:log:';
const LOG_INDEX = 'dialer:log:index';
const LOG_ARCHIVE_PREFIX = 'dialer:log:archive:';

function createDialerLogRepo(redis) {
  return {
    async create(entry) {
      const record = {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        ...entry,
      };
      await redis.multi().set(`${LOG_PREFIX}${record.id}`, JSON.stringify(record)).zadd(LOG_INDEX, Date.now(), record.id).exec();
      return record;
    },
    async archiveOlderThan(maxAgeMs = 24 * 60 * 60 * 1000) {
      const cutoff = Date.now() - maxAgeMs;
      const ids = await redis.zrangebyscore(LOG_INDEX, 0, cutoff);
      for (const id of ids) {
        const key = `${LOG_PREFIX}${id}`;
        const raw = await redis.get(key);
        if (raw) {
          await redis.set(`${LOG_ARCHIVE_PREFIX}${id}`, raw);
          await redis.del(key);
        }
        await redis.zrem(LOG_INDEX, id);
      }
      return ids.length;
    },
  };
}

module.exports = { createDialerLogRepo };
