const apiBaseUrl = import.meta.env.VITE_API_BASE_URL;

export async function fetchVoiceToken(identity: string): Promise<string> {
  if (!apiBaseUrl) {
    throw new Error("Missing VITE_API_BASE_URL");
  }

  const response = await fetch(`${apiBaseUrl}/api/voice/token?identity=${identity}`);

  if (!response.ok) {
    throw new Error(`Failed to fetch voice token: ${response.status}`);
  }

  const data = (await response.json()) as { token?: string };

  if (typeof data.token !== "string" || data.token.length === 0) {
    throw new Error("Voice token response did not include token");
  }

  return data.token;
}
