import { assertApiResponse } from "../../lib/assertApiResponse";
import { api } from "../../network/api";

type OtpStartPayload = {
  challengeId: string;
};

type OtpVerifyPayload = {
  verified: boolean;
};

type TelephonyTokenPayload = {
  token: string;
};

export async function startOtp(phone: string): Promise<OtpStartPayload> {
  const response = await api.post("/api/otp/start", { phone });
  return assertApiResponse<OtpStartPayload>(response.data);
}

export async function verifyOtp(code: string): Promise<OtpVerifyPayload> {
  const response = await api.post("/api/otp/verify", { code });
  return assertApiResponse<OtpVerifyPayload>(response.data);
}

export async function getTelephonyToken(): Promise<TelephonyTokenPayload> {
  const response = await api.get("/api/telephony/token");
  return assertApiResponse<TelephonyTokenPayload>(response.data);
}

export async function completeTelephonyAuthFlow(
  phone = "system",
  code = "system"
): Promise<TelephonyTokenPayload> {
  await startOtp(phone);
  const verify = await verifyOtp(code);

  if (verify.verified !== true) {
    throw new Error("Request failed");
  }

  const token = await getTelephonyToken();

  if (!token.token) {
    throw new Error("Request failed");
  }

  return token;
}
