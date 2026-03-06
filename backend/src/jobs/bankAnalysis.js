function parseTransactions(payload) {
  return payload.transactions || [];
}

function computeBalances(transactions) {
  return transactions.reduce((sum, tx) => sum + Number(tx.amount || 0), 0);
}

function detectNSFs(transactions) {
  return transactions.filter((tx) => String(tx.type).toLowerCase() === 'nsf');
}

function generateSummary(transactions, totalBalance, nsfs) {
  return {
    transaction_count: transactions.length,
    total_balance: totalBalance,
    nsf_count: nsfs.length,
  };
}

async function runBankAnalysis(payload, deps = {}) {
  const { apiClient } = deps;
  const transactions = parseTransactions(payload);
  const totalBalance = computeBalances(transactions);
  const nsfs = detectNSFs(transactions);
  const summary = generateSummary(transactions, totalBalance, nsfs);

  const body = {
    applicationId: payload.applicationId,
    transactions,
    totalBalance,
    nsfs,
    summary,
  };

  await apiClient.post('/api/banking/analysis', body);
  return body;
}

module.exports = { runBankAnalysis, parseTransactions, computeBalances, detectNSFs, generateSummary };
