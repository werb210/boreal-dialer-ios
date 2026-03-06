import { Call, Device } from "@twilio/voice-sdk";
import { bindCallSession, cleanupCall } from "../../services/callSession";
import { logCall } from "../../services/callLogger";
import { emitPortalCallEvent } from "../../services/portalEvents";
import { registerIncomingCallHandler } from "../../services/incomingCallHandler";
import { fetchVoiceToken } from "../../services/twilioTokenService";
import {
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setCallStatus,
  setDevice,
  setNetworkBanner,
  useCallStore
} from "../state/callStore";

let deviceInstance: Device | null = null;
let initializing: Promise<Device> | null = null;

function getClientId(call: Call): string | null {
  const from = String(call.parameters.From ?? "");
  if (from.startsWith("client:")) {
    return from.replace("client:", "");
  }

  return null;
}

async function registerCallEnd(call: Call, direction: "inbound" | "outbound") {
  const { callDuration } = getCallStoreState();

  await logCall({
    direction,
    from: String(call.parameters.From ?? "unknown"),
    to: String(call.parameters.To ?? "unknown"),
    startedAt: new Date(Date.now() - callDuration * 1000).toISOString(),
    endedAt: new Date().toISOString(),
    duration: callDuration,
    clientId: getClientId(call)
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
    const newToken = await fetchVoiceToken();
    await device.updateToken(newToken);
  });

  device.on("offline", async () => {
    setNetworkBanner("Connection lost. Attempting reconnect.");

    try {
      const token = await fetchVoiceToken();
      await device.updateToken(token);
      setNetworkBanner(null);
    } catch {
      setNetworkBanner("Connection lost. Attempting reconnect.");
    }
  });

  device.on("ready", () => {
    setNetworkBanner(null);
  });
}

export async function getVoiceDevice(): Promise<Device> {
  if (deviceInstance) {
    return deviceInstance;
  }

  if (initializing) {
    return initializing;
  }

  initializing = (async () => {
    const token = await fetchVoiceToken();

    const options = {
      codecPreferences: ["opus", "pcmu"],
      enableRingingState: true,
      logLevel: 1
    } as unknown as ConstructorParameters<typeof Device>[1];

    const device = new Device(token, options);

    bindDeviceLifecycle(device);
    setDevice(device);

    deviceInstance = device;
    return device;
  })().finally(() => {
    initializing = null;
  });

  return initializing;
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
  setCallStatus("in-call");

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
  deviceInstance = null;
  initializing = null;
}
