import { getDialerAuthState } from "../auth/useDialerAuth";

type TwilioTokenResponse = {
  token: string;
  identity?: string;
};

let tokenPromise: Promise<TwilioTokenResponse> | null = null;

function buildHeaders(): HeadersInit {
  const { token } = getDialerAuthState();

  if (!token) {
    return {};
  }

  return {
    Authorization: `Bearer ${token}`
  };
}

export async function getTwilioToken(): Promise<TwilioTokenResponse> {
  if (tokenPromise) {
    return tokenPromise;
  }

  const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? "";

  tokenPromise = fetch(`${apiBaseUrl}/api/voice/token`, {
    method: "GET",
    headers: buildHeaders()
  })
    .then(async (response) => {
      if (!response.ok) {
        throw new Error(`Failed to fetch voice token: ${response.status}`);
      }

      const data = (await response.json()) as Partial<TwilioTokenResponse>;

      if (typeof data.token !== "string" || data.token.length === 0) {
        throw new Error("Voice token response did not include token");
      }

      return {
        token: data.token,
        identity: data.identity
      };
    })
    .finally(() => {
      tokenPromise = null;
    });

  return tokenPromise;
}
