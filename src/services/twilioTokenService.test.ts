import { beforeEach, describe, expect, it, vi } from "vitest";
import { getTwilioToken } from "./twilioTokenService";

vi.mock("../auth/useDialerAuth", () => ({
  getDialerAuthState: () => ({ token: "jwt-token" })
}));

describe("twilioTokenService", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.stubEnv("VITE_API_BASE_URL", "http://localhost:3000");
  });

  it("queues concurrent refreshes into a single request", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({ token: "abc", identity: "staff-1" })
    } as Response);

    const [a, b, c] = await Promise.all([
      getTwilioToken(),
      getTwilioToken(),
      getTwilioToken()
    ]);

    expect(a.token).toBe("abc");
    expect(b.token).toBe("abc");
    expect(c.token).toBe("abc");
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });
});
