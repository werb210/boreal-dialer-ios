import { beforeEach, describe, expect, it, vi } from "vitest";
import { __resetAuthFlowForTests, runTelephonyAuthFlow } from "./telephonyAuthFlow";

const order: string[] = [];

const hoisted = vi.hoisted(() => ({
  post: vi.fn(async (url: string, _data: unknown, config?: { timeout?: number }) => {
    if (config?.timeout !== 5000) {
      throw new Error("TIMEOUT_NOT_SET");
    }

    if (url === "/api/auth/otp/start") {
      order.push("startOtp");
      return { data: { success: true, data: { challengeId: "challenge-1" } } };
    }

    if (url === "/api/auth/otp/verify") {
      order.push("verifyOtp");
      return { data: { success: true, data: { verified: true } } };
    }

    throw new Error(`Unexpected POST URL: ${url}`);
  }),
  get: vi.fn(async (url: string, config?: { timeout?: number }) => {
    if (config?.timeout !== 5000) {
      throw new Error("TIMEOUT_NOT_SET");
    }

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

describe("telephonyAuthFlow", () => {
  beforeEach(() => {
    order.length = 0;
    vi.clearAllMocks();
    __resetAuthFlowForTests();
  });

  it("runs otp -> verify -> telephony token in strict order", async () => {
    const data = await runTelephonyAuthFlow("+15550000000", "123456", async () => ({ deviceId: "device-1" }));

    expect(data.token).toBe("token-xyz");
    expect(order).toEqual(["startOtp", "verifyOtp", "getTelephonyToken"]);
  });

  it("fails hard for malformed API responses", async () => {
    hoisted.post.mockResolvedValueOnce({ data: { success: false } });

    await expect(
      runTelephonyAuthFlow("+15550000000", "123456", async () => ({ deviceId: "device-1" }))
    ).rejects.toThrow("INVALID API RESPONSE");
  });

  it("fails fast on timeout errors", async () => {
    hoisted.post.mockRejectedValueOnce(new Error("timeout of 5000ms exceeded"));

    await expect(
      runTelephonyAuthFlow("+15550000000", "123456", async () => ({ deviceId: "device-1" }))
    ).rejects.toThrow("timeout");
  });

  it("rejects parallel auth executions", async () => {
    hoisted.post.mockImplementationOnce(
      async () =>
        await new Promise((resolve) => {
          setTimeout(() => resolve({ data: { success: true, data: { challengeId: "challenge-1" } } }), 20);
        })
    );

    const runA = runTelephonyAuthFlow("+15550000000", "123456", async () => ({ deviceId: "device-1" }));

    await expect(
      runTelephonyAuthFlow("+15550000000", "123456", async () => ({ deviceId: "device-1" }))
    ).rejects.toThrow("AUTH_ALREADY_RUNNING");

    await expect(runA).resolves.toEqual({ token: "token-xyz" });
  });

  it("fails when auth output is incomplete", async () => {
    await expect(runTelephonyAuthFlow("+15550000000", "123456", async () => ({ deviceId: "" }))).rejects.toThrow(
      "AUTH FLOW INCOMPLETE"
    );
  });
});
