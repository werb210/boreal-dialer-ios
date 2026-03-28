import { describe, expect, it } from "vitest";
import { createAuthFlow } from "../telephony/services/telephonyAuthFlow";

describe("createAuthFlow", () => {
  it("enforces strict auth flow order", async () => {
    const calls: string[] = [];

    const flow = createAuthFlow({
      requestOTP: async () => {
        calls.push("otp");
      },
      verifyOTP: async () => {
        calls.push("verify");
      },
      getToken: async () => {
        calls.push("token");
        return { token: "token-abc" };
      },
      initDevice: async () => {
        calls.push("device");
      }
    });

    await flow.run();

    expect(calls).toEqual(["otp", "verify", "token", "device"]);
  });
});
