import { Device, Call } from "@twilio/voice-sdk";
import {
  clearAll,
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setIncomingCall
} from "../state/callStore";

let device: Device | null = null;

function bindCallLifecycle(call: Call) {
  call.on("accept", () => {
    setActiveCall(call);
    clearIncomingCall();
  });

  call.on("disconnect", () => {
    clearAll();
  });

  call.on("cancel", () => {
    if (getCallStoreState().incomingCall === call) {
      clearIncomingCall();
    }
  });

  call.on("reject", () => {
    if (getCallStoreState().incomingCall === call) {
      clearIncomingCall();
    }
  });
}

export function registerVoiceDevice(token: string) {
  if (device) {
    device.destroy();
  }

  clearAll();
  device = new Device(token);

  device.on("incoming", (call: Call) => {
    setIncomingCall(call);
    bindCallLifecycle(call);
  });

  device.on("disconnect", () => {
    clearAll();
  });

  device.on("error", (error: Error) => {
    throw new Error(`Twilio device error: ${error.message}`);
  });
}

export async function initializeVoice(token: string) {
  registerVoiceDevice(token);
}

export async function startCall(to: string) {
  if (!device) {
    throw new Error("Device not initialized");
  }

  const call = await device.connect({ params: { To: to } });
  bindCallLifecycle(call);
  setActiveCall(call);
}

export function hangupCall() {
  const { activeCall } = getCallStoreState();

  if (activeCall) {
    activeCall.disconnect();
  }

  clearAll();
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

export function muteCall() {
  getCallStoreState().activeCall?.mute(true);
}

export function unmuteCall() {
  getCallStoreState().activeCall?.mute(false);
}
