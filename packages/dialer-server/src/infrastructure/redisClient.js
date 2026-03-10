import Redis from 'ioredis';

let redis;

function getRedisClient(redisUrl = process.env.REDIS_URL) {
  if (!redis) {
    redis = new Redis(redisUrl, {
      maxRetriesPerRequest: 1,
      enableReadyCheck: true,
      lazyConnect: false,
    });
  }
  return redis;
}

export { getRedisClient };
