import { assertApiResponse } from "../../lib/assertApiResponse";
import { api } from "../../network/api";

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
  if (!payload || typeof payload !== "object") {
    throw new Error("MALFORMED_OTP_RESPONSE");
  }

  const token = (payload as { token?: unknown }).token;
  if (typeof token !== "string" || token.trim().length === 0) {
    throw new Error("MALFORMED_OTP_RESPONSE");
  }

  return { token };
}

function assertTelephonyTokenPayload(payload: unknown): TelephonyTokenPayload {
  if (!payload || typeof payload !== "object") {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  const token = (payload as { token?: unknown }).token;
  if (typeof token !== "string" || token.trim().length === 0) {
    throw new Error("MALFORMED_TWILIO_TOKEN_RESPONSE");
  }

  return { token };
}

async function startOtp(phone: string): Promise<OtpStartPayload> {
  const response = await api.post("/api/auth/otp/start", { phone }, { timeout: 5000 });
  assertEnvelopeShape(response.data);
  return assertApiResponse<OtpStartPayload>(response.data);
}

async function verifyOtp(phone: string, code: string): Promise<OtpVerifyPayload> {
  const response = await api.post("/api/auth/otp/verify", { phone, code }, { timeout: 5000 });
  assertEnvelopeShape(response.data);
  return assertOtpVerifyPayload(assertApiResponse<unknown>(response.data));
}

async function getTelephonyToken(): Promise<TelephonyTokenPayload> {
  const response = await api.get("/api/telephony/token", { timeout: 5000 });
  assertEnvelopeShape(response.data);
  return assertTelephonyTokenPayload(assertApiResponse<unknown>(response.data));
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
