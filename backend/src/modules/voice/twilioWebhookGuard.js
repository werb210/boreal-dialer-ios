function validateTwilioSignature(req, res, next) {
  if (process.env.NODE_ENV === 'test') {
    return next();
  }

  const signature = req.headers['x-twilio-signature'];
  if (!signature) {
    return res.status(403).json({ error: 'invalid_twilio_signature' });
  }

  const twilio = require('twilio');
  const authToken = process.env.TWILIO_AUTH_TOKEN || req.app?.locals?.env?.TWILIO_AUTH_TOKEN;
  const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
  const url = `${baseUrl}${req.originalUrl}`;

  const isValid = twilio.validateRequest(authToken, signature, url, req.body || {});
  if (!isValid) {
    return res.status(403).json({ error: 'invalid_twilio_signature' });
  }

  return next();
}

module.exports = { validateTwilioSignature };
