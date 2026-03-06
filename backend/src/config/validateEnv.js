const REQUIRED_ENV_VARS = ['OPENAI_API_KEY', 'BF_SERVER_API', 'MAYA_SECRET'];

function validateEnv(env = process.env) {
  for (const key of REQUIRED_ENV_VARS) {
    if (!env[key]) {
      throw new Error(`${key} missing`);
    }
  }
}

module.exports = { validateEnv, REQUIRED_ENV_VARS };
