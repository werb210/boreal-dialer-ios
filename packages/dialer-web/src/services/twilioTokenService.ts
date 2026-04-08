import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";
import { registerAuthResetter } from "../auth/useDialerAuth";

type TokenPayload = {
  token: string;
  ttl?: number;
};

let cachedToken: string | null = null;
let tokenExpiry = 0;

function clearCachedToken(): void {
  cachedToken = null;
  tokenExpiry = 0;
}

registerAuthResetter(clearCachedToken);

function assertTwilioTokenPayload(payload: unknown): TokenPayload {
  if (!payload || typeof payload !== "object") {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  const { token, ttl } = payload as { token?: unknown; ttl?: unknown };
  if (typeof token !== "string" || token.trim().length < 10) {
    throw new Error("MALFORMED_TWILIO_TOKEN");
  }

  if (ttl !== undefined && typeof ttl !== "number") {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  return { token, ttl: ttl as number | undefined };
}

export async function getVoiceToken(): Promise<string> {
  const now = Date.now();

  if (cachedToken && now < tokenExpiry) {
    return cachedToken;
  }

  try {
    const response = await api.get(TELEPHONY_TOKEN_ENDPOINT);
    const data = assertTwilioTokenPayload(assertApiResponse<unknown>(response.data));

    if (!data?.token) {
      throw new Error("MALFORMED_TWILIO_TOKEN");
    }

    cachedToken = data.token;
    tokenExpiry = now + (data.ttl ?? 3600) * 1000;

    return data.token;
  } catch (error) {
    const endpoint = TELEPHONY_TOKEN_ENDPOINT;
    const status = typeof error === "object" && error && "response" in error ? (error as { response?: { status?: number } }).response?.status : undefined;
    const message = error instanceof Error ? error.message : String(error);
    console.error("[auth] token fetch failed", { endpoint, status: status ?? "unknown", message });
    throw error;
  }
}

export async function fetchVoiceToken(): Promise<string> {
  try {
    const response = await api.get(TELEPHONY_TOKEN_ENDPOINT);
    const data = assertTwilioTokenPayload(assertApiResponse<unknown>(response.data));

    if (!data?.token) {
      throw new Error("MALFORMED_TWILIO_TOKEN");
    }

    return data.token;
  } catch (error) {
    const endpoint = TELEPHONY_TOKEN_ENDPOINT;
    const status = typeof error === "object" && error && "response" in error ? (error as { response?: { status?: number } }).response?.status : undefined;
    const message = error instanceof Error ? error.message : String(error);
    console.error("[auth] token fetch failed", { endpoint, status: status ?? "unknown", message });
    throw error;
  }
}

export async function getTwilioToken(): Promise<TokenPayload> {
  const token = await getVoiceToken();
  return { token };
}
