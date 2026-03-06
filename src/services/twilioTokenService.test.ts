import { beforeEach, describe, expect, it, vi } from "vitest";
import { fetchVoiceToken } from "./twilioTokenService";

describe("twilioTokenService", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("fetches a voice token from staff API", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({ token: "abc" })
    } as Response);

    await expect(fetchVoiceToken()).resolves.toBe("abc");
    expect(globalThis.fetch).toHaveBeenCalledWith("/api/twilio/voice-token");
  });
});
