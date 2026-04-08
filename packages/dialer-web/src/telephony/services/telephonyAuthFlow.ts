import { assertApiResponse } from "../../lib/assertApiResponse";
import { api } from "../../network/api";
import { fetchVoiceToken } from "../../services/twilioTokenService";

type OtpStartPayload = {
  challengeId: string;
};

type OtpVerifyPayload = {
  token: string;
};

type TelephonyTokenPayload = {
  token: string;
};

type AuthFlow = {
  run: () => Promise<TelephonyTokenPayload>;
};

type AuthFlowHandlers = {
  requestOTP: () => Promise<OtpStartPayload>;
  verifyOTP: () => Promise<OtpVerifyPayload>;
  getToken: () => Promise<TelephonyTokenPayload>;
  initDevice: () => Promise<{ deviceId: string }>;
};

let authInProgress = false;

function assertEnvelopeShape(response: unknown) {
  if (!response || typeof response !== "object" || !("success" in response) || (response as { success?: boolean }).success !== true) {
    throw new Error("INVALID API RESPONSE");
  }
}

function assertOtpVerifyPayload(payload: unknown): OtpVerifyPayload {
  const token = (payload as { token?: string } | undefined)?.token;
  if (!token) {
    throw new Error("INVALID_OTP_RESPONSE");
  }

  return { token };
}

async function startOtp(phone: string): Promise<OtpStartPayload> {
  const response = await api.post("/api/auth/otp/start", { phone }, { timeout: 5000 });
  assertEnvelopeShape(response.data);
  return assertApiResponse<OtpStartPayload>(response.data);
}

async function verifyOtp(phone: string, code: string): Promise<OtpVerifyPayload> {
  const endpoint = "/api/auth/otp/verify";
  try {
    const response = await api.post(endpoint, { phone, code }, { timeout: 5000 });
    assertEnvelopeShape(response.data);
    const payload = assertApiResponse<unknown>(response.data);
    return assertOtpVerifyPayload(payload);
  } catch (error) {
    console.error("[INVARIANT_VIOLATION]", error);
    throw error;
  }
}

async function getTelephonyToken(): Promise<TelephonyTokenPayload> {
  const token = await fetchVoiceToken(5000);
  if (!token) {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  return { token };
}

function createAuthFlow(handlers: AuthFlowHandlers): AuthFlow {
  return {
    async run() {
      if (authInProgress) {
        throw new Error("AUTH_ALREADY_RUNNING");
      }

      authInProgress = true;

      try {
        const otp = await handlers.requestOTP();
        const verify = await handlers.verifyOTP();
        const token = await handlers.getToken();
        const { deviceId } = await handlers.initDevice();

        if (!otp.challengeId || !verify.token || !token.token || !deviceId) {
          throw new Error("AUTH FLOW INCOMPLETE");
        }

        return token;
      } finally {
        authInProgress = false;
      }
    }
  };
}

export async function runTelephonyAuthFlow(
  phone = "system",
  code = "system",
  initDevice: () => Promise<{ deviceId: string }> = async () => ({ deviceId: "system" })
): Promise<TelephonyTokenPayload> {
  const flow = createAuthFlow({
    requestOTP: async () => {
      const response = await startOtp(phone);
      if (!response || typeof response !== "object") {
        throw new Error("INVALID API RESPONSE");
      }
      return response;
    },
    verifyOTP: async () => verifyOtp(phone, code),
    getToken: async () => getTelephonyToken(),
    initDevice
  });

  return flow.run();
}

export function __resetAuthFlowForTests() {
  authInProgress = false;
}
