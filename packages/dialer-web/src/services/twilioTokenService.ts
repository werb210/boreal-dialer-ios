import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";
import { getDialerAuthState, registerAuthResetter } from "../auth/useDialerAuth";
import { isTokenExpired } from "../auth/token";

type TokenPayload = {
  token: string;
  ttl?: number;
};

let telephonyToken: string | null = null;
let tokenExpiry = 0;
let tokenInvalidated = false;
let refreshPromise: Promise<string> | null = null;

function clearCachedToken(): void {
  if (telephonyToken) {
    tokenInvalidated = true;
  }
  telephonyToken = null;
  tokenExpiry = 0;
  refreshPromise = null;
}

function ensureAuthInitialized(): void {
  if (!getDialerAuthState().initialized) {
    throw new Error("AUTH_NOT_INITIALIZED");
  }
}

function isExpired(token: string): boolean {
  if (!token) {
    return true;
  }

  if (isTokenExpired(token)) {
    return true;
  }

  return Date.now() >= tokenExpiry;
}

registerAuthResetter(clearCachedToken);

function assertTwilioTokenPayload(payload: unknown): TokenPayload {
  if (!payload || typeof payload !== "object") {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  const { token, ttl } = payload as { token?: unknown; ttl?: unknown };
  if (typeof token !== "string" || token.trim().length < 100) {
    throw new Error("MALFORMED_TWILIO_TOKEN");
  }

  if (ttl !== undefined && typeof ttl !== "number") {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  return { token, ttl: ttl as number | undefined };
}

function logInvariantViolation(error: unknown): void {
  console.error("[INVARIANT_VIOLATION]", error);
}

async function fetchTokenPayload(timeout?: number): Promise<TokenPayload> {
  const response = timeout
    ? await api.get(TELEPHONY_TOKEN_ENDPOINT, { timeout })
    : await api.get(TELEPHONY_TOKEN_ENDPOINT);
  return assertTwilioTokenPayload(assertApiResponse<unknown>(response.data));
}

export async function getVoiceToken(): Promise<string> {
  ensureAuthInitialized();

  if (tokenInvalidated && telephonyToken) {
    throw new Error("TOKEN_ALREADY_INVALIDATED");
  }

  if (telephonyToken && !isExpired(telephonyToken)) {
    return telephonyToken;
  }

  if (refreshPromise) {
    return refreshPromise;
  }

  refreshPromise = (async () => {
    const data = await fetchTokenPayload();

    telephonyToken = data.token;
    tokenInvalidated = false;
    tokenExpiry = Date.now() + (data.ttl ?? 3600) * 1000;

    return data.token;
  })();

  try {
    return await refreshPromise;
  } catch (error) {
    logInvariantViolation(error);
    throw error;
  } finally {
    refreshPromise = null;
  }
}

export async function fetchVoiceToken(timeout?: number): Promise<string> {
  ensureAuthInitialized();

  try {
    const data = await fetchTokenPayload(timeout);
    return data.token;
  } catch (error) {
    logInvariantViolation(error);
    throw error;
  }
}

export async function getTwilioToken(): Promise<TokenPayload> {
  const token = await getVoiceToken();
  return { token };
}

export function clearTwilioTokenForTests(): void {
  clearCachedToken();
  tokenInvalidated = false;
}
