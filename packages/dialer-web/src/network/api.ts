import axios, { type InternalAxiosRequestConfig } from "axios";
import { clearAuth, getValidAuthToken } from "../auth/useDialerAuth";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

const configuredApiUrl = import.meta.env.VITE_API_URL;

if (!configuredApiUrl || configuredApiUrl.trim() === "") {
  throw new Error("MISSING_VITE_API_URL");
}

function logInvariantViolation(error: unknown): void {
  console.error("[INVARIANT_VIOLATION]", error);
}

function toPathname(url: string): string {
  if (!url) {
    return "";
  }

  if (url.startsWith("/")) {
    return url;
  }

  try {
    return new URL(url, configuredApiUrl).pathname;
  } catch {
    return url;
  }
}

function withRequestGuards(config: InternalAxiosRequestConfig): InternalAxiosRequestConfig {
  const path = toPathname(String(config.url ?? ""));

  if (!/^\/(api|voice|calls)\//.test(path)) {
    throw new Error(`INVALID_API_PATH: ${path}`);
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
