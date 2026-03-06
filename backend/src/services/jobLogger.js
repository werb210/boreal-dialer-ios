function createJobLogger() {
  const logs = [];

  function log(entry) {
    logs.push({
      ...entry,
      timestamp: entry.timestamp || new Date().toISOString(),
    });
  }

  return {
    logStarted(job) {
      log({
        job_id: job.id,
        job_type: job.type,
        status: 'started',
        started_at: new Date().toISOString(),
        finished_at: null,
        error: null,
      });
    },
    logCompleted(job, startedAt) {
      log({
        job_id: job.id,
        job_type: job.type,
        status: 'completed',
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        error: null,
      });
    },
    logFailed(job, startedAt, error) {
      log({
        job_id: job.id,
        job_type: job.type,
        status: 'failed',
        started_at: startedAt,
        finished_at: new Date().toISOString(),
        error: error ? String(error.message || error) : 'unknown_error',
      });
    },
    list() {
      return [...logs];
    },
  };
}

module.exports = { createJobLogger };
