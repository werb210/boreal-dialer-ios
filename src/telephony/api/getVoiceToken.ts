import { getTwilioToken } from "../../services/twilioTokenService";

type VoiceTokenResponse = {
  token: string;
};

export async function getVoiceToken(): Promise<VoiceTokenResponse> {
  const data = await getTwilioToken();
  return { token: data.token };
}
