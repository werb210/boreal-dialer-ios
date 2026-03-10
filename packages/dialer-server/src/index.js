const { createServer } = require('./server');
const { validateEnv } = require('./config/env');

const env = validateEnv(process.env);
const { server } = createServer(env);

const port = Number(process.env.PORT || 3001);
server.listen(port, () => {
  // structured logger is used in server internals.
});
