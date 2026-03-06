async function notifyMessage(payload, deps = {}) {
  return {
    applicationId: payload.applicationId,
    clientId: payload.clientId,
    channels: ['portal_notification', 'browser_push'],
    messageId: payload.messageId,
  };
}

module.exports = { notifyMessage };
