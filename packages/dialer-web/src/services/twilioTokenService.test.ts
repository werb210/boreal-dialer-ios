import { beforeEach, describe, expect, it, vi } from "vitest";

const hoisted = vi.hoisted(() => ({
  get: vi.fn(async () => ({ data: { success: true, data: { token: "abc", ttl: 60 } } }))
}));

vi.mock("../network/api", () => ({
  api: {
    get: hoisted.get
  }
}));

import { fetchVoiceToken, getVoiceToken } from "./twilioTokenService";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

describe("twilioTokenService", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("fetches a voice token from API envelope", async () => {
    await expect(fetchVoiceToken()).resolves.toBe("abc");
    expect(hoisted.get).toHaveBeenCalledWith(TELEPHONY_TOKEN_ENDPOINT);
  });

  it("caches token responses", async () => {
    await expect(getVoiceToken()).resolves.toBe("abc");
    await expect(getVoiceToken()).resolves.toBe("abc");
    expect(hoisted.get).toHaveBeenCalledTimes(1);
  });
});
