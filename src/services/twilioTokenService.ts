export async function fetchVoiceToken(): Promise<string> {
  const response = await fetch("/api/twilio/voice-token");

  if (!response.ok) {
    throw new Error("Failed to fetch voice token");
  }

  const data = (await response.json()) as { token?: string };

  if (typeof data.token !== "string" || data.token.length === 0) {
    throw new Error("Failed to fetch voice token");
  }

  return data.token;
}

export async function getTwilioToken(): Promise<{ token: string; identity?: string }> {
  const token = await fetchVoiceToken();
  return { token };
}
