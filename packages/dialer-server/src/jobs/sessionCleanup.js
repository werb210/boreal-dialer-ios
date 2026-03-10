function startSessionCleanup({ voiceSessionsRepo, presenceRepo, dialerLogRepo, logger }) {
  const timer = setInterval(async () => {
    try {
      const removedSessions = await voiceSessionsRepo.removeExpiredSessions();
      await presenceRepo.removeStale();
      const archivedLogs = await dialerLogRepo.archiveOlderThan();
      logger.info({ event: 'session_cleanup_completed', removedSessions, archivedLogs });
    } catch (error) {
      logger.error({ event: 'session_cleanup_failed', err: error.message });
    }
  }, 60000);

  if (typeof timer.unref === 'function') timer.unref();
  return () => clearInterval(timer);
}

module.exports = { startSessionCleanup };
