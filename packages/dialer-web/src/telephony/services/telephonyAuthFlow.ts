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
  requestOTP: () => Promise<void>;
  verifyOTP: () => Promise<void>;
  getToken: () => Promise<TelephonyTokenPayload>;
  initDevice: () => Promise<void>;
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

export function createAuthFlow(handlers: AuthFlowHandlers): AuthFlow {
  return {
    async run() {
      await handlers.requestOTP();
      await handlers.verifyOTP();
      const token = await handlers.getToken();
      await handlers.initDevice();
      return token;
    }
  };
}

export async function completeTelephonyAuthFlow(
  phone = "system",
  code = "system",
  initDevice: () => Promise<void> = async () => undefined
): Promise<TelephonyTokenPayload> {
  const flow = createAuthFlow({
    requestOTP: async () => {
      await startOtp(phone);
    },
    verifyOTP: async () => {
      const verify = await verifyOtp(code);
      if (verify.verified !== true) {
        throw new Error("OTP verification failed");
      }
    },
    getToken: async () => {
      const token = await getTelephonyToken();
      if (!token.token) {
        throw new Error("Missing telephony token");
      }
      return token;
    },
    initDevice
  });

  return flow.run();
}
