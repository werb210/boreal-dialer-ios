function detectDocumentType(payload) {
  if (payload.documentType) return payload.documentType;
  const name = String(payload.filename || '').toLowerCase();
  if (name.includes('bank')) return 'bank_statement';
  if (name.includes('id')) return 'id_document';
  return 'generic_document';
}

async function runDocumentOCR(payload, deps = {}) {
  const { runOCR = async () => ({ text: '' }), apiClient } = deps;
  const documentId = payload.documentId;
  const documentUrl = payload.documentUrl;

  const documentType = detectDocumentType(payload);
  const result = await runOCR(documentUrl, documentType);

  await apiClient.post('/documents/ocr-result', {
    documentId,
    documentType,
    result,
  });

  return { documentId, documentType, result };
}

module.exports = { runDocumentOCR, detectDocumentType };
