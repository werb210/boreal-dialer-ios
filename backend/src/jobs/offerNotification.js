async function notifyOffer(payload, deps = {}) {
  const { apiClient } = deps;
  const body = {
    applicationId: payload.applicationId,
    clientId: payload.clientId,
    channels: ['sms', 'portal_message', 'push_notification'],
    offerId: payload.offerId,
  };
  await apiClient.post('/api/notifications/offer', body);
  return body;
}

module.exports = { notifyOffer };
