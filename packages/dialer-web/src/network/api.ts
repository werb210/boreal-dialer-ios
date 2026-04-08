import axios, { type InternalAxiosRequestConfig } from "axios";
import { clearAuth, getValidAuthToken } from "../auth/useDialerAuth";
import { API_BASE, API_ENDPOINTS, TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

const configuredApiUrl = API_BASE;

function logInvariantViolation(error: unknown): void {
  console.error("[INVARIANT_VIOLATION]", error);
}

function toAbsoluteUrl(url: string): string {
  if (!url) {
    return "";
  }

  try {
    return new URL(url, configuredApiUrl).toString();
  } catch {
    return url;
  }
}

function withRequestGuards(config: InternalAxiosRequestConfig): InternalAxiosRequestConfig {
  const rawUrl = String(config.url ?? "");
  const absoluteUrl = toAbsoluteUrl(rawUrl);
  const path = new URL(absoluteUrl, configuredApiUrl).pathname;

  const allowedPaths = new Set<string>(Object.values(API_ENDPOINTS));
  const isAllowed = [...allowedPaths].some((allowedPath) => path === allowedPath || path.startsWith(`${allowedPath}/`));

  if (!isAllowed || !absoluteUrl.startsWith(API_BASE)) {
    throw new Error(`INVALID_API_PATH: ${absoluteUrl}`);
  }

  if (path.includes(TELEPHONY_TOKEN_ENDPOINT) && path !== TELEPHONY_TOKEN_ENDPOINT) {
    throw new Error("INVALID_TELEPHONY_ENDPOINT");
  }

  const token = getValidAuthToken();

  if (!token) {
    return config;
  }

  const headers = config.headers ?? {};
  headers.Authorization = `Bearer ${token}`;
  config.headers = headers;
  return config;
}

export const api = axios.create({
  baseURL: configuredApiUrl,
  timeout: 5000,
  headers: {
    "Content-Type": "application/json"
  }
});

if (import.meta.env.DEV) {
  console.assert(Object.isFrozen(API_ENDPOINTS), "API_ENDPOINTS must be frozen");
  console.assert(API_BASE.startsWith("http"), "API_BASE must be absolute");
}

api.interceptors.request.use((config) => {
  try {
    return withRequestGuards(config);
  } catch (error) {
    if (error instanceof Error && error.message === "INVALID_AUTH_TOKEN") {
      clearAuth();
    }

    logInvariantViolation(error);
    return Promise.reject(error);
  }
});
