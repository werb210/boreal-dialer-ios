import { beforeEach, describe, expect, it, vi } from "vitest";

const hoisted = vi.hoisted(() => ({
  get: vi.fn(async () => ({ data: { success: true, data: { token: "token-abc-".padEnd(120, "x"), ttl: 60 } } })),
  getDialerAuthState: vi.fn(() => ({ token: null, initialized: true })),
  registerAuthResetter: vi.fn(() => () => undefined)
}));

vi.mock("../network/api", () => ({
  api: {
    get: hoisted.get
  }
}));

vi.mock("../auth/useDialerAuth", () => ({
  getDialerAuthState: hoisted.getDialerAuthState,
  registerAuthResetter: hoisted.registerAuthResetter
}));

import { fetchVoiceToken, getVoiceToken } from "./twilioTokenService";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

describe("twilioTokenService", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("fetches a voice token from API envelope", async () => {
    await expect(fetchVoiceToken()).resolves.toBe("token-abc-".padEnd(120, "x"));
    expect(hoisted.get).toHaveBeenCalledWith(TELEPHONY_TOKEN_ENDPOINT);
  });

  it("caches token responses", async () => {
    await expect(getVoiceToken()).resolves.toBe("token-abc-".padEnd(120, "x"));
    await expect(getVoiceToken()).resolves.toBe("token-abc-".padEnd(120, "x"));
    expect(hoisted.get).toHaveBeenCalledTimes(1);
  });
});
