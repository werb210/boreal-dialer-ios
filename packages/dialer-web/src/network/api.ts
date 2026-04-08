import axios, { type InternalAxiosRequestConfig } from "axios";
import { getValidAuthToken, logout } from "../auth/useDialerAuth";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

const configuredApiUrl = import.meta.env.VITE_API_URL;

if (!configuredApiUrl || configuredApiUrl.trim() === "") {
  throw new Error("INVALID_API_BASE_URL");
}

function assertTelephonyEndpointContract(url: string): void {
  if (url.includes("/voice") || url.includes("/calls") || url.includes("/twilio")) {
    throw new Error("INVALID_TELEPHONY_ENDPOINT");
  }
}

function withRequestGuards(config: InternalAxiosRequestConfig): InternalAxiosRequestConfig {
  const url = String(config.url ?? "");
  assertTelephonyEndpointContract(url);

  if (url.includes("/telephony/token") && url !== TELEPHONY_TOKEN_ENDPOINT) {
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
      logout();
    }

    return Promise.reject(error);
  }
});
