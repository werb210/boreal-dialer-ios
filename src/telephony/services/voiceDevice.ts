import { Call, Device } from "@twilio/voice-sdk";
import { fetchVoiceToken } from "../../services/twilioTokenService";
import {
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setCallStatus,
  setDevice,
  setIncomingCall,
  setNetworkBanner
} from "../state/callStore";

let device: Device | null = null;
let initializing: Promise<Device> | null = null;

async function refreshToken(currentDevice: Device) {
  const next = await fetchVoiceToken();
  await currentDevice.updateToken(next);
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
    setNetworkBanner("Connection lost. Attempting reconnect.");
    await refreshToken(currentDevice);
  });

  currentDevice.on("error", () => {
    setNetworkBanner("Connection lost. Attempting reconnect.");
  });
}

export async function initVoiceDevice() {
  if (device) {
    return device;
  }

  if (!initializing) {
    initializing = (async () => {
      const token = await fetchVoiceToken();
      const nextDevice = new Device(token, {
        codecPreferences: [Call.Codec.Opus, Call.Codec.PCMU]
      });

      bindDeviceEvents(nextDevice);
      setDevice(nextDevice);
      device = nextDevice;
      return nextDevice;
    })().finally(() => {
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

export function __resetVoiceDeviceForTests() {
  device = null;
  initializing = null;
  setDevice(null);
  setIncomingCall(null);
  setActiveCall(null);
  setCallStatus("idle");
  setNetworkBanner(null);
}

export async function startCall(to: string) {
  const currentDevice = await initVoiceDevice();
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
