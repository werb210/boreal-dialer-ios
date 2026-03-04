import { Call, Device } from "@twilio/voice-sdk";
import { getVoiceToken } from "../api/getVoiceToken";
import {
  clearAllCalls,
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setDevice,
  setIncomingCall,
  useCallStore
} from "../state/callStore";

let initializePromise: Promise<void> | null = null;

function clearCallReferences(call: Call) {
  const { activeCall, incomingCall } = getCallStoreState();

  if (activeCall === call || incomingCall === call) {
    clearAllCalls();
  }
}

function bindCallLifecycle(call: Call) {
  call.on("accept", () => {
    setActiveCall(call);
    clearIncomingCall();
  });

  call.on("disconnect", () => {
    clearCallReferences(call);
  });

  call.on("cancel", () => {
    clearCallReferences(call);
  });

  call.on("reject", () => {
    clearCallReferences(call);
  });
}

function bindDeviceLifecycle(device: Device) {
  device.on("incoming", (call: Call) => {
    setIncomingCall(call);
    bindCallLifecycle(call);
  });

  device.on("disconnect", () => {
    clearAllCalls();
  });
}

async function createAndRegisterDevice(): Promise<void> {
  const { token } = await getVoiceToken();
  const device = new Device(token);

  bindDeviceLifecycle(device);
  await device.register();
  setDevice(device);
}

export async function initializeVoice(): Promise<void> {
  if (getCallStoreState().device) {
    return;
  }

  if (!initializePromise) {
    initializePromise = createAndRegisterDevice().finally(() => {
      initializePromise = null;
    });
  }

  await initializePromise;
}

export async function startCall(to: string): Promise<Call> {
  const { device } = getCallStoreState();

  if (!device) {
    throw new Error("Device not initialized");
  }

  const call = await device.connect({ params: { To: to } });

  bindCallLifecycle(call);
  setActiveCall(call);

  return call;
}

export function hangupCall() {
  getCallStoreState().activeCall?.disconnect();
  clearAllCalls();
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
}

export function rejectIncomingCall() {
  const { incomingCall } = getCallStoreState();

  if (!incomingCall) {
    return;
  }

  incomingCall.reject();
  clearIncomingCall();
}

export function getCallState() {
  return getCallStoreState();
}

export { useCallStore };
