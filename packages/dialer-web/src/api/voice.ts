import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";

type VoiceTokenPayload = {
  token: string;
};

export async function fetchVoiceToken(identity: string): Promise<string> {
  const response = await api.get("/api/voice/token", {
    params: { identity }
  });

  const data = assertApiResponse<VoiceTokenPayload>(response.data);

  if (typeof data.token !== "string" || data.token.length === 0) {
    throw new Error("Voice token response did not include token");
  }

  return data.token;
}
