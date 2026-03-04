import { getDialerAuthState } from "../../auth/useDialerAuth";

const STAFF_MOBILE_IDENTITY = "staff_mobile";

type VoiceTokenResponse = {
  token: string;
};

function buildHeaders(): HeadersInit {
  const { token } = getDialerAuthState();

  if (!token) {
    return {};
  }

  return {
    Authorization: `Bearer ${token}`
  };
}

export async function getVoiceToken(): Promise<VoiceTokenResponse> {
  const apiBaseUrl = import.meta.env.VITE_API_BASE_URL;

  if (!apiBaseUrl) {
    throw new Error("Missing VITE_API_BASE_URL");
  }

  const response = await fetch(
    `${apiBaseUrl}/api/voice/token?identity=${STAFF_MOBILE_IDENTITY}`,
    {
      method: "GET",
      headers: buildHeaders()
    }
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch voice token: ${response.status}`);
  }

  const data = (await response.json()) as Partial<VoiceTokenResponse>;

  if (typeof data.token !== "string" || data.token.length === 0) {
    throw new Error("Voice token response did not include token");
  }

  return { token: data.token };
}
