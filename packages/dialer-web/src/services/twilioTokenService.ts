import axios from "axios";

type TokenResponse = {
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

  const res = await axios.get<TokenResponse>("/api/calls/token");

  cachedToken = res.data.token;
  tokenExpiry = now + (res.data.ttl ?? 3600) * 1000;

  return res.data.token;
}

export async function fetchVoiceToken(): Promise<string> {
  const response = await fetch("/api/twilio/voice-token");
  if (!response.ok) {
    throw new Error("Failed to fetch voice token");
  }

  const data = (await response.json()) as TokenResponse;
  return data.token;
}

export async function getTwilioToken(): Promise<TokenResponse> {
  const token = await getVoiceToken();
  return { token };
}
