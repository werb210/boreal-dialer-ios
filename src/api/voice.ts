const apiBaseUrl =
  import.meta.env.API_BASE_URL ??
  (typeof process !== "undefined" ? process.env.API_BASE_URL : undefined);

export async function fetchVoiceToken(identity: string) {
  const res = await fetch(`${apiBaseUrl}/api/voice/token?identity=${identity}`);

  const data = await res.json();

  return data.token;
}
