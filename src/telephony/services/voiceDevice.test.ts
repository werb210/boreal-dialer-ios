import { beforeEach, describe, expect, it, vi } from "vitest";
import { clearStore, getCallStoreState } from "../state/callStore";
import {
  answerIncomingCall,
  getCallState,
  initializeVoice,
  startCall
} from "./voiceDevice";

type MockCall = {
  parameters: { From?: string };
  on: (event: string, handler: () => void) => void;
  emit: (event: string) => void;
  accept: ReturnType<typeof vi.fn>;
  reject: ReturnType<typeof vi.fn>;
  disconnect: ReturnType<typeof vi.fn>;
  mute: ReturnType<typeof vi.fn>;
};

type MockDevice = {
  register: ReturnType<typeof vi.fn>;
  connect: ReturnType<typeof vi.fn>;
  on: (event: string, handler: (call?: MockCall) => void) => void;
  emit: (event: string, call?: MockCall) => void;
};

const hoisted = vi.hoisted(() => ({
  getTwilioToken: vi.fn(async () => ({ token: "token-123", identity: "staff-1" })),
  createCall: null as ((from?: string) => MockCall) | null
}));

vi.mock("../../services/twilioTokenService", () => ({
  getTwilioToken: hoisted.getTwilioToken
}));

vi.mock("../../services/callLogger", () => ({
  logCall: vi.fn(async () => undefined)
}));

vi.mock("@twilio/voice-sdk", () => {
  function createCall(from?: string): MockCall {
    const handlers: Record<string, Array<() => void>> = {};

    const call: MockCall = {
      parameters: { From: from, To: "+15551234567" },
      on(event, handler) {
        handlers[event] ??= [];
        handlers[event].push(handler);
      },
      emit(event) {
        handlers[event]?.forEach((handler) => {
          handler();
        });
      },
      accept: vi.fn(),
      reject: vi.fn(),
      disconnect: vi.fn(() => {
        call.emit("disconnect");
      }),
      mute: vi.fn()
    };

    return call;
  }

  class Device {
    register = vi.fn(async () => undefined);
    connect = vi.fn(async () => createCall("outbound"));
    private handlers: Record<string, Array<(call?: MockCall) => void>> = {};

    on(event: string, handler: (call?: MockCall) => void) {
      this.handlers[event] ??= [];
      this.handlers[event].push(handler);
    }

    emit(event: string, call?: MockCall) {
      this.handlers[event]?.forEach((handler) => {
        handler(call);
      });
    }
  }

  hoisted.createCall = createCall;

  return { Device, Call: class {} };
});

describe("voiceDevice", () => {
  beforeEach(() => {
    clearStore();
    vi.clearAllMocks();
  });

  it("startCall stores a resolved call and clears state on disconnect", async () => {
    await initializeVoice();

    const call = await startCall("+15551234567");

    expect(call).toBeDefined();
    expect(getCallState().activeCall).toBe(call);

    call.disconnect();

    expect(getCallState().activeCall).toBeNull();
    expect(getCallState().incomingCall).toBeNull();
  });

  it("incoming call is stored and answer promotes it to active call", async () => {
    await initializeVoice();

    const device = getCallStoreState().device as unknown as MockDevice;
    const incomingCall = hoisted.createCall?.("client_42");

    if (!incomingCall) {
      throw new Error("Mock call factory unavailable");
    }

    device.emit("incoming", incomingCall);

    expect(getCallState().incomingCall).toBe(incomingCall);

    answerIncomingCall();

    expect(incomingCall.accept).toHaveBeenCalledTimes(1);
    expect(getCallState().activeCall).toBe(incomingCall);
    expect(getCallState().incomingCall).toBeNull();
  });

  it("uses a single token refresh queue for concurrent initialization", async () => {
    await Promise.all([initializeVoice(), initializeVoice(), initializeVoice()]);

    expect(hoisted.getTwilioToken).toHaveBeenCalledTimes(1);
  });

  it("cleans call session for cancel/reject/error", async () => {
    await initializeVoice();
    const device = getCallStoreState().device as unknown as MockDevice;
    const incomingCall = hoisted.createCall?.("client_99");

    if (!incomingCall) {
      throw new Error("Mock call factory unavailable");
    }

    device.emit("incoming", incomingCall);
    incomingCall.emit("cancel");
    expect(getCallState().incomingCall).toBeNull();

    device.emit("incoming", incomingCall);
    incomingCall.emit("reject");
    expect(getCallState().incomingCall).toBeNull();

    device.emit("incoming", incomingCall);
    incomingCall.emit("error");
    expect(getCallState().incomingCall).toBeNull();
  });
});
