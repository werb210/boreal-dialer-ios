const { handlers } = require('../jobs');
const { createJobLogger } = require('../services/jobLogger');

const queue = [];
const recentJobs = new Map();
let running = false;

const RETRY_LIMIT = 3;
const RECENT_JOB_TTL_MS = 30_000;
const logger = createJobLogger();

function buildJobKey(job) {
  const entityId = job.payload?.entityId || job.payload?.documentId || job.payload?.applicationId || job.payload?.messageId || 'unknown';
  return `${job.type}:${entityId}`;
}

function cleanupRecentJobs(now = Date.now()) {
  for (const [key, timestamp] of recentJobs.entries()) {
    if (now - timestamp > RECENT_JOB_TTL_MS) recentJobs.delete(key);
  }
}

async function enqueue(job, deps = {}) {
  cleanupRecentJobs();
  const key = buildJobKey(job);

  if (recentJobs.has(key)) {
    return false;
  }

  recentJobs.set(key, Date.now());
  queue.push(job);
  if (!running) {
    processQueue(deps).catch((error) => {
      console.error('Queue processing crashed', error);
      running = false;
    });
  }

  return true;
}

async function processQueue(deps = {}) {
  if (running) return;
  running = true;

  while (queue.length) {
    const job = queue.shift();
    if (!job) continue;
    await executeJob(job, deps);
  }

  running = false;
}

async function executeJob(job, deps = {}, attempt = 0) {
  const startedAt = new Date().toISOString();
  const handler = deps.handlers?.[job.type] || handlers[job.type];
  const delay = deps.delay || ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));

  if (!handler) {
    console.error('Unknown job type', job.type);
    return;
  }

  logger.logStarted(job);

  try {
    await Promise.resolve().then(() => handler(job.payload, deps));
    logger.logCompleted(job, startedAt);
  } catch (error) {
    if (attempt < RETRY_LIMIT) {
      await delay(1000 * (attempt + 1));
      return executeJob(job, deps, attempt + 1);
    }

    logger.logFailed(job, startedAt, error);
    console.error('Job permanently failed', job.id, error);
  }
}

function getQueueHealth() {
  return {
    status: 'ok',
    queue_length: queue.length,
    workers: 1,
  };
}

function getJobLogs() {
  return logger.list();
}

function resetQueueState() {
  queue.length = 0;
  recentJobs.clear();
  running = false;
}

module.exports = {
  enqueue,
  processQueue,
  executeJob,
  getQueueHealth,
  getJobLogs,
  resetQueueState,
  RETRY_LIMIT,
};
