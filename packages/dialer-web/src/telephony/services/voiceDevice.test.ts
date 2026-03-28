import { beforeEach, describe, expect, it, vi } from "vitest";
import { clearStore, getCallStoreState } from "../state/callStore";
import {
  __getSessionForTests,
  __resetVoiceDeviceForTests,
  __setSessionForTests,
  getDevice,
  startDialerSession
} from "./voiceDevice";

type EventHandler = (...args: unknown[]) => unknown;

type MockDevice = {
  updateToken: ReturnType<typeof vi.fn>;
  on: (event: string, handler: EventHandler) => void;
  emit: (event: string, ...args: unknown[]) => Promise<void>;
  connect: ReturnType<typeof vi.fn>;
  state: string;
};

const hoisted = vi.hoisted(() => ({
  runTelephonyAuthFlow: vi.fn(async () => ({ token: "token-123" }))
}));

vi.mock("./telephonyAuthFlow", () => ({
  runTelephonyAuthFlow: hoisted.runTelephonyAuthFlow
}));

vi.mock("../../services/callLogger", () => ({
  logCall: vi.fn(async () => undefined)
}));

vi.mock("@twilio/voice-sdk", () => ({
  Device: class {
    token: string;
    options: unknown;
    handlers: Record<string, EventHandler[]> = {};
    state = "unregistered";
    updateToken = vi.fn(async () => undefined);
    connect = vi.fn(async () => ({ id: "call-1" }));
    register = vi.fn(async () => {
      this.state = "registered";
      await this.emit("registered");
    });

    constructor(token: string, options: unknown) {
      this.token = token;
      this.options = options;
    }

    on(event: string, handler: EventHandler) {
      this.handlers[event] ??= [];
      this.handlers[event].push(handler);
    }

    async emit(event: string, ...args: unknown[]) {
      await Promise.all((this.handlers[event] ?? []).map((handler) => handler(...args)));
    }
  },
  Call: class {
    static Codec = { Opus: "opus", PCMU: "pcmu" };
  }
}));

describe("voiceDevice", () => {
  beforeEach(() => {
    clearStore();
    __resetVoiceDeviceForTests();
    vi.clearAllMocks();
  });

  it("enforces singleton creation", async () => {
    const [a, b, c] = await Promise.all([startDialerSession(), startDialerSession(), startDialerSession()]);

    expect(a).toBe(b);
    expect(b).toBe(c);
    expect(hoisted.runTelephonyAuthFlow).toHaveBeenCalledTimes(1);
  });

  it("refreshes token on tokenWillExpire", async () => {
    const device = (await startDialerSession()) as unknown as MockDevice;

    hoisted.runTelephonyAuthFlow.mockResolvedValueOnce({ token: "token-refresh" });
    await device.emit("tokenWillExpire");

    expect(device.updateToken).toHaveBeenCalledWith("token-refresh");
  });

  it("attempts token refresh when device goes offline", async () => {
    const device = (await startDialerSession()) as unknown as MockDevice;

    hoisted.runTelephonyAuthFlow.mockResolvedValueOnce({ token: "token-reconnect" });
    await device.emit("offline");

    expect(device.updateToken).toHaveBeenCalledWith("token-reconnect");
    expect(getCallStoreState().networkBanner).toBeNull();
  });

  it("blocks calls without an authenticated session", async () => {
    await startDialerSession();
    __setSessionForTests({ isAuthenticated: false });

    await expect(startDialerSession("+15551234567")).rejects.toThrow("NOT_AUTHENTICATED");
  });

  it("allows connect only after registered state", async () => {
    await startDialerSession();
    await expect(startDialerSession("+15551234567")).resolves.toBeTruthy();
  });

  it("keeps state unregistered and token empty on auth failure", async () => {
    hoisted.runTelephonyAuthFlow.mockRejectedValueOnce(new Error("AUTH FAILED"));

    await expect(startDialerSession()).rejects.toThrow("AUTH FAILED");
    expect((getDevice() as unknown as MockDevice | null)?.state ?? "unregistered").toBe("unregistered");
    expect(__getSessionForTests().token).toBeUndefined();
    expect(__getSessionForTests().isAuthenticated).toBe(false);
  });
});
