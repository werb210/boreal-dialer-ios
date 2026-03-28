import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";

type TokenPayload = {
  token: string;
  ttl?: number;
};

let cachedToken: string | null = null;
let tokenExpiry = 0;

export async function getVoiceToken(): Promise<string> {
  const now = Date.now();

  if (cachedToken && now < tokenExpiry) {
    return cachedToken;
  }

  const response = await api.get("/api/calls/token");
  const data = assertApiResponse<TokenPayload>(response.data);

  cachedToken = data.token;
  tokenExpiry = now + (data.ttl ?? 3600) * 1000;

  return data.token;
}

export async function fetchVoiceToken(): Promise<string> {
  const response = await api.get("/api/twilio/voice-token");
  const data = assertApiResponse<TokenPayload>(response.data);
  return data.token;
}

export async function getTwilioToken(): Promise<TokenPayload> {
  const token = await getVoiceToken();
  return { token };
}
