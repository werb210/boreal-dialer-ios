const crypto = require('crypto');
const { EventEmitter } = require('events');
const { enqueue } = require('../queue/jobQueue');

function registerSystemEvents(eventBus = new EventEmitter(), deps = {}) {
  const queueEnqueue = deps.enqueue || enqueue;

  eventBus.on('application_created', async (payload) => {
    await queueEnqueue({ id: crypto.randomUUID(), type: 'application_summary', payload });
  });

  eventBus.on('document_uploaded', async (payload) => {
    await queueEnqueue({ id: crypto.randomUUID(), type: 'document_ocr', payload });

    if (payload.documentType === 'bank_statement') {
      await queueEnqueue({ id: crypto.randomUUID(), type: 'bank_statement_analysis', payload });
    }
  });

  eventBus.on('documents_complete', async (payload) => {
    await queueEnqueue({ id: crypto.randomUUID(), type: 'application_summary', payload });
  });

  eventBus.on('offer_created', async (payload) => {
    await queueEnqueue({ id: crypto.randomUUID(), type: 'offer_notification', payload });
  });

  eventBus.on('offer_accepted', async (payload) => {
    await queueEnqueue({ id: crypto.randomUUID(), type: 'message_notification', payload });
  });

  eventBus.on('message_received', async (payload) => {
    await queueEnqueue({ id: crypto.randomUUID(), type: 'message_notification', payload });
  });

  return eventBus;
}

module.exports = { registerSystemEvents };
