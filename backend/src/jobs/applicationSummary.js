function toMemo({ application, bankAnalysis, ocr, websiteScan }) {
  return {
    Transaction: application.transaction || 'N/A',
    Overview: application.overview || 'N/A',
    Collateral: application.collateral || 'N/A',
    'Financial Summary': {
      bankAnalysis,
      ocr,
      websiteScan,
    },
    Risks: application.risks || 'N/A',
    Rationale: application.rationale || 'N/A',
  };
}

async function generateSummary(payload, deps = {}) {
  const { apiClient } = deps;
  const memo = toMemo(payload);

  await apiClient.post('/api/credit-summary', {
    applicationId: payload.application.id,
    memo,
  });

  return memo;
}

module.exports = { generateSummary, toMemo };
