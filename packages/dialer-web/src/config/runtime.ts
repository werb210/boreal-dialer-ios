export type RuntimeEnv = {
  NODE_ENV?: string;
  API_URL?: string;
};

function resolveProcessEnv(): RuntimeEnv {
  const processRef = (globalThis as { process?: { env?: RuntimeEnv } }).process;
  return processRef?.env ?? {};
}

export function getRuntimeEnv(): RuntimeEnv {
  return resolveProcessEnv();
}
