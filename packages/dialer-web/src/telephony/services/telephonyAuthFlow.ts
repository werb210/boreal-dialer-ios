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

async function startOtp(phone: string): Promise<OtpStartPayload> {
  const response = await api.post("/api/otp/start", { phone }, { timeout: 5000 });
  assertEnvelopeShape(response.data);
  return assertApiResponse<OtpStartPayload>(response.data);
}

async function verifyOtp(code: string): Promise<OtpVerifyPayload> {
  const response = await api.post("/api/otp/verify", { code }, { timeout: 5000 });
  assertEnvelopeShape(response.data);
  return assertApiResponse<OtpVerifyPayload>(response.data);
}

async function getTelephonyToken(): Promise<TelephonyTokenPayload> {
  const response = await api.get("/api/telephony/token", { timeout: 5000 });
  assertEnvelopeShape(response.data);
  return assertApiResponse<TelephonyTokenPayload>(response.data);
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

        if (verify.verified !== true || !otp.challengeId || !token.token || !deviceId) {
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
    verifyOTP: async () => {
      const verify = await verifyOtp(code);
      if (!verify || typeof verify !== "object") {
        throw new Error("INVALID API RESPONSE");
      }
      return verify;
    },
    getToken: async () => {
      const token = await getTelephonyToken();
      if (!token || typeof token !== "object") {
        throw new Error("INVALID API RESPONSE");
      }
      return token;
    },
    initDevice
  });

  return flow.run();
}

export function __resetAuthFlowForTests() {
  authInProgress = false;
}
