import { beforeEach, describe, expect, it, vi } from "vitest";
import { clearStore, getCallStoreState } from "../state/callStore";
import { __resetVoiceDeviceForTests, getVoiceDevice, initializeVoice, startCall } from "./voiceDevice";

type EventHandler = (...args: unknown[]) => unknown;

type MockDevice = {
  updateToken: ReturnType<typeof vi.fn>;
  on: (event: string, handler: EventHandler) => void;
  emit: (event: string, ...args: unknown[]) => Promise<void>;
  connect: ReturnType<typeof vi.fn>;
};

const hoisted = vi.hoisted(() => ({
  completeTelephonyAuthFlow: vi.fn(async () => ({ token: "token-123" }))
}));

vi.mock("./telephonyAuthFlow", () => ({
  completeTelephonyAuthFlow: hoisted.completeTelephonyAuthFlow
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
    const [a, b, c] = await Promise.all([
      getVoiceDevice(),
      getVoiceDevice(),
      initializeVoice().then(() => getVoiceDevice())
    ]);

    expect(a).toBe(b);
    expect(b).toBe(c);
    expect(hoisted.completeTelephonyAuthFlow).toHaveBeenCalledTimes(1);
  });

  it("refreshes token on tokenWillExpire", async () => {
    const device = (await getVoiceDevice()) as unknown as MockDevice;

    hoisted.completeTelephonyAuthFlow.mockResolvedValueOnce({ token: "token-refresh" });
    await device.emit("tokenWillExpire");

    expect(device.updateToken).toHaveBeenCalledWith("token-refresh");
  });

  it("attempts token refresh when device goes offline", async () => {
    const device = (await getVoiceDevice()) as unknown as MockDevice;

    hoisted.completeTelephonyAuthFlow.mockResolvedValueOnce({ token: "token-reconnect" });
    await device.emit("offline");

    expect(device.updateToken).toHaveBeenCalledWith("token-reconnect");
    expect(getCallStoreState().networkBanner).toBeNull();
  });

  it("allows connect only after ready", async () => {
    await getVoiceDevice();
    await expect(startCall("+15551234567")).resolves.toBeTruthy();
  });
});
