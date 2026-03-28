import { Call, Device } from "@twilio/voice-sdk";
import {
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setCallStatus,
  setDevice,
  setIncomingCall,
  setNetworkBanner
} from "../state/callStore";
import { completeTelephonyAuthFlow } from "./telephonyAuthFlow";

let device: Device | null = null;
let deviceReady = false;
let initializing: Promise<Device> | null = null;

async function refreshToken(currentDevice: Device) {
  const { token } = await completeTelephonyAuthFlow();
  await currentDevice.updateToken(token);
  setNetworkBanner(null);
}

function bindDeviceEvents(currentDevice: Device) {
  currentDevice.on("incoming", (call: Call) => {
    setIncomingCall(call);
    setCallStatus("ringing");
  });

  currentDevice.on("tokenWillExpire", async () => {
    await refreshToken(currentDevice);
  });

  currentDevice.on("offline", async () => {
    deviceReady = false;
    setNetworkBanner("Connection lost. Attempting reconnect.");
    await refreshToken(currentDevice);
  });

  currentDevice.on("error", () => {
    deviceReady = false;
    setNetworkBanner("Connection lost. Attempting reconnect.");
  });

  currentDevice.on("registered", () => {
    deviceReady = true;
    setNetworkBanner(null);
  });
}

export async function initializeDevice() {
  if (device) {
    return device;
  }

  const { token } = await completeTelephonyAuthFlow();
  if (!token) {
    throw new Error("Request failed");
  }

  const nextDevice = new Device(token, {
    codecPreferences: [Call.Codec.Opus, Call.Codec.PCMU]
  });

  bindDeviceEvents(nextDevice);
  setDevice(nextDevice);
  device = nextDevice;

  await nextDevice.register();
  deviceReady = true;

  return device;
}

export async function initVoiceDevice() {
  if (!initializing) {
    initializing = initializeDevice().finally(() => {
      initializing = null;
    });
  }

  return initializing;
}

export async function initializeVoice() {
  return initVoiceDevice();
}

export async function getVoiceDevice() {
  return initVoiceDevice();
}

export function getDevice() {
  return device;
}

export function __resetVoiceDeviceForTests() {
  device = null;
  deviceReady = false;
  initializing = null;
  setDevice(null);
  setIncomingCall(null);
  setActiveCall(null);
  setCallStatus("idle");
  setNetworkBanner(null);
}

export async function startCall(to: string) {
  const currentDevice = await initVoiceDevice();
  if (!device || (device as Device & { state?: string }).state !== "registered") {
    throw new Error("Device not ready");
  }

  const call = await currentDevice.connect({ params: { to } });
  setActiveCall(call);
  setCallStatus("connecting");
  return call;
}

export function answerIncomingCall() {
  const { incomingCall } = getCallStoreState();
  incomingCall?.accept();
  setActiveCall(incomingCall);
  clearIncomingCall();
  setCallStatus("in-call");
}

export function rejectIncomingCall() {
  const { incomingCall } = getCallStoreState();
  incomingCall?.reject();
  clearIncomingCall();
  setCallStatus("ended");
}

export function hangupCall() {
  const { activeCall } = getCallStoreState();
  activeCall?.disconnect();
  setActiveCall(null);
  setCallStatus("ended");
}

export function muteCall() {
  const { activeCall } = getCallStoreState();
  activeCall?.mute(true);
}

export function unmuteCall() {
  const { activeCall } = getCallStoreState();
  activeCall?.mute(false);
}
