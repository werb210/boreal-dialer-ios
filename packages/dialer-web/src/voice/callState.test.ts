import { describe, expect, it, vi } from "vitest";
import { clearActiveCall, getActiveCall, setActiveCall } from "./callState";

describe("callState", () => {
  it("disconnects old call when setting a new active call", () => {
    const oldCall = { disconnect: vi.fn() };
    const newCall = { disconnect: vi.fn() };

    setActiveCall(oldCall);
    setActiveCall(newCall);

    expect(oldCall.disconnect).toHaveBeenCalledTimes(1);
    expect(getActiveCall()).toBe(newCall);

    clearActiveCall();
    expect(getActiveCall()).toBeNull();
  });
});
