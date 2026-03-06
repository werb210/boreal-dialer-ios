const { runDocumentOCR } = require('./documentOcr');
const { runBankAnalysis } = require('./bankAnalysis');
const { generateSummary } = require('./applicationSummary');
const { notifyOffer } = require('./offerNotification');
const { notifyMessage } = require('./messageNotification');

const handlers = {
  document_ocr: runDocumentOCR,
  bank_statement_analysis: runBankAnalysis,
  application_summary: generateSummary,
  offer_notification: notifyOffer,
  message_notification: notifyMessage,
};

module.exports = { handlers };
