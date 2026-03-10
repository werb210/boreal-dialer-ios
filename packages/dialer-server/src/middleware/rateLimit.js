const rateLimit = require('express-rate-limit');

const voiceRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
});

module.exports = { voiceRateLimit };
