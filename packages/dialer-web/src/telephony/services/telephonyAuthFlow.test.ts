import { describe, expect, it, vi } from "vitest";
import { completeTelephonyAuthFlow } from "./telephonyAuthFlow";
import { initializeDevice, __resetVoiceDeviceForTests } from "./voiceDevice";

const order: string[] = [];

const hoisted = vi.hoisted(() => ({
  post: vi.fn(async (url: string) => {
    if (url === "/api/otp/start") {
      order.push("startOtp");
      return { data: { success: true, data: { challengeId: "challenge-1" } } };
    }

    if (url === "/api/otp/verify") {
      order.push("verifyOtp");
      return { data: { success: true, data: { verified: true } } };
    }

    throw new Error(`Unexpected POST URL: ${url}`);
  }),
  get: vi.fn(async (url: string) => {
    if (url === "/api/telephony/token") {
      order.push("getTelephonyToken");
      return { data: { success: true, data: { token: "token-xyz" } } };
    }

    throw new Error(`Unexpected GET URL: ${url}`);
  })
}));

vi.mock("../../network/api", () => ({
  api: {
    post: hoisted.post,
    get: hoisted.get
  }
}));

vi.mock("@twilio/voice-sdk", () => ({
  Device: class {
    register = vi.fn(async () => undefined);
    on = vi.fn();
    constructor(public token: string) {}
  },
  Call: class {
    static Codec = { Opus: "opus", PCMU: "pcmu" };
  }
}));

describe("telephonyAuthFlow", () => {
  it("runs otp -> verify -> telephony token in strict order", async () => {
    const data = await completeTelephonyAuthFlow("+15550000000", "123456");

    expect(data.token).toBe("token-xyz");
    expect(order).toEqual(["startOtp", "verifyOtp", "getTelephonyToken"]);
  });

  it("initializes device after telephony token is obtained", async () => {
    __resetVoiceDeviceForTests();
    order.length = 0;

    const device = await initializeDevice();

    expect(device).toBeTruthy();
    expect(order).toEqual(["startOtp", "verifyOtp", "getTelephonyToken"]);
  });
});
