import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";
import { registerAuthResetter } from "../auth/useDialerAuth";
import { isTokenExpired } from "../auth/token";

type TokenPayload = {
  token: string;
  ttl?: number;
};

let telephonyToken: string | null = null;
let tokenExpiry = 0;

function clearCachedToken(): void {
  telephonyToken = null;
  tokenExpiry = 0;
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
  if (typeof token !== "string" || token.trim().length === 0) {
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
  if (telephonyToken && !isExpired(telephonyToken)) {
    return telephonyToken;
  }

  try {
    const data = await fetchTokenPayload();

    telephonyToken = data.token;
    tokenExpiry = Date.now() + (data.ttl ?? 3600) * 1000;

    return data.token;
  } catch (error) {
    logInvariantViolation(error);
    throw error;
  }
}

export async function fetchVoiceToken(timeout?: number): Promise<string> {
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
}
