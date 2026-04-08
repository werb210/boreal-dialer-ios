import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";

type TokenPayload = {
  token: string;
  ttl?: number;
};

let cachedToken: string | null = null;
let tokenExpiry = 0;

function assertTwilioTokenPayload(payload: unknown): TokenPayload {
  if (!payload || typeof payload !== "object") {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  const { token, ttl } = payload as { token?: unknown; ttl?: unknown };
  if (typeof token !== "string" || token.trim().length === 0) {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
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
    const response = await api.get("/api/telephony/token");
    const data = assertTwilioTokenPayload(assertApiResponse<unknown>(response.data));

    if (!data?.token) {
      throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
    }

    cachedToken = data.token;
    tokenExpiry = now + (data.ttl ?? 3600) * 1000;

    return data.token;
  } catch (error) {
    const endpoint = "/api/telephony/token";
    const status = typeof error === "object" && error && "response" in error ? (error as { response?: { status?: number } }).response?.status : undefined;
    const message = error instanceof Error ? error.message : String(error);
    console.error("[auth] token fetch failed", { endpoint, status: status ?? "unknown", message });
    throw error;
  }
}

export async function fetchVoiceToken(): Promise<string> {
  try {
    const response = await api.get("/api/telephony/token");
    const data = assertTwilioTokenPayload(assertApiResponse<unknown>(response.data));

    if (!data?.token) {
      throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
    }

    return data.token;
  } catch (error) {
    const endpoint = "/api/telephony/token";
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
