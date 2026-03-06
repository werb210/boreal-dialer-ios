import { Call, Device } from "@twilio/voice-sdk";
import { getTwilioToken } from "../../services/twilioTokenService";
import { bindCallSession, cleanupCall } from "../../services/callSession";
import { logCall } from "../../services/callLogger";
import { emitPortalCallEvent } from "../../services/portalEvents";
import { registerIncomingCallHandler } from "../../services/incomingCallHandler";
import {
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setCallStatus,
  setDevice,
  setNetworkBanner,
  useCallStore
} from "../state/callStore";

let device: Device | null = null;
let initializePromise: Promise<Device> | null = null;

async function retryConnect(device: Device, attempt = 0): Promise<void> {
  try {
    await device.register();
    setNetworkBanner(null);
  } catch {
    const delay = Math.min(5000, 500 * 2 ** attempt);
    setTimeout(() => {
      void retryConnect(device, attempt + 1);
    }, delay);
  }
}

function getClientId(call: Call): string | null {
  const from = String(call.parameters.From ?? "");
  if (from.startsWith("client:")) {
    return from.replace("client:", "");
  }

  return null;
}

async function registerCallEnd(call: Call, direction: "inbound" | "outbound") {
  const { callDuration } = getCallStoreState();
  const { identity } = await getTwilioToken();

  await logCall({
    staff_id: identity ?? "unknown",
    client_id: getClientId(call),
    phone_number: String(call.parameters.To ?? call.parameters.From ?? "unknown"),
    call_duration: callDuration,
    call_direction: direction,
    timestamp: new Date().toISOString()
  });

  emitPortalCallEvent("call_ended", {
    direction,
    duration: callDuration,
    phoneNumber: String(call.parameters.To ?? call.parameters.From ?? "unknown")
  });
}

function bindDeviceLifecycle(device: Device) {
  registerIncomingCallHandler(device);

  device.on("incoming", (call: Call) => {
    bindCallSession(call);
  });

  device.on("tokenWillExpire", async () => {
    const { token } = await getTwilioToken();
    await device.updateToken(token);
  });

  device.on("offline", () => {
    setNetworkBanner("Connection lost. Attempting reconnect.");
    void retryConnect(device);
  });

  if (typeof window !== "undefined") {
    window.addEventListener("online", () => {
      void retryConnect(device);
    });
  }

  device.on("error", () => {
    setCallStatus("error");
    setNetworkBanner("Device error");
  });
}

async function createAndRegisterDevice(): Promise<Device> {
  const existing = getCallStoreState().device;
  if (existing) {
    return existing;
  }

  const { token } = await getTwilioToken();

  const voiceDeviceOptions = {
    codecPreferences: [Call.Codec.Opus, Call.Codec.PCMU],
    fakeLocalDTMF: true,
    enableRingingState: true
  } as unknown as ConstructorParameters<typeof Device>[1];

  const nextDevice = new Device(token, voiceDeviceOptions);

  bindDeviceLifecycle(nextDevice);
  await retryConnect(nextDevice);
  setDevice(nextDevice);
  device = nextDevice;

  return nextDevice;
}

export async function getVoiceDevice(): Promise<Device> {
  if (device) {
    if (!getCallStoreState().device) {
      setDevice(device);
    }
    return device;
  }

  const storeDevice = getCallStoreState().device;
  if (storeDevice) {
    device = storeDevice;
    return storeDevice;
  }

  if (!initializePromise) {
    initializePromise = createAndRegisterDevice().finally(() => {
      initializePromise = null;
    });
  }

  return initializePromise;
}

export async function initializeVoice(): Promise<void> {
  await getVoiceDevice();
}

export async function startCall(to: string): Promise<Call> {
  const { device } = getCallStoreState();

  if (!device) {
    throw new Error("Device not initialized");
  }

  setCallStatus("connecting");

  const call = await device.connect({ params: { To: to } });

  bindCallSession(call);
  setActiveCall(call);

  emitPortalCallEvent("call_started", { phoneNumber: to });

  call.on("accept", () => {
    emitPortalCallEvent("call_answered", { phoneNumber: to });
  });

  call.on("disconnect", () => {
    void registerCallEnd(call, "outbound");
  });

  call.on("cancel", () => {
    void registerCallEnd(call, "outbound");
  });

  call.on("reject", () => {
    void registerCallEnd(call, "outbound");
  });

  call.on("error", () => {
    setNetworkBanner("Call failed");
    void registerCallEnd(call, "outbound");
  });

  return call;
}

export function hangupCall() {
  getCallStoreState().activeCall?.disconnect();
  cleanupCall(getCallStoreState().activeCall ?? undefined);
}

export function muteCall() {
  getCallStoreState().activeCall?.mute(true);
}

export function unmuteCall() {
  getCallStoreState().activeCall?.mute(false);
}

export function answerIncomingCall() {
  const { incomingCall } = getCallStoreState();

  if (!incomingCall) {
    return;
  }

  incomingCall.accept();
  setActiveCall(incomingCall);
  clearIncomingCall();
  setCallStatus("connected");

  emitPortalCallEvent("call_answered", {
    phoneNumber: String(incomingCall.parameters.From ?? "unknown")
  });

  incomingCall.on("disconnect", () => {
    void registerCallEnd(incomingCall, "inbound");
  });
}

export function rejectIncomingCall() {
  const { incomingCall } = getCallStoreState();

  if (!incomingCall) {
    return;
  }

  incomingCall.reject();
  cleanupCall(incomingCall);
  setCallStatus("ended");
}

export function getCallState() {
  return getCallStoreState();
}

export { useCallStore };

export function __resetVoiceDeviceForTests() {
  device = null;
  initializePromise = null;
}
