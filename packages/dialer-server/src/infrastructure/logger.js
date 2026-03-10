const pino = require('pino');

const logger = pino({
  base: null,
  timestamp: pino.stdTimeFunctions.isoTime,
});

function logEvent(level, payload) {
  logger[level]({
    callSid: payload.callSid || null,
    sessionId: payload.sessionId || null,
    staffId: payload.staffId || null,
    event: payload.event || 'unknown_event',
    ...payload,
  });
}

module.exports = { logger, logEvent };
