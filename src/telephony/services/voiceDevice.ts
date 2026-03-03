import { Device, Call } from "@twilio/voice-sdk";

let device: Device | null = null;
let activeCall: Call | null = null;

export async function initializeVoice(identity: string) {
  const res = await fetch("/telephony/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ identity })
  });

  const { token } = await res.json();

  device = new Device(token, {
    codecPreferences: ["opus", "pcmu"],
    closeProtection: true
  });

  device.on("incoming", (call: Call) => {
    activeCall = call;
  });

  device.register();
}

export function getDevice() {
  return device;
}

export function getActiveCall() {
  return activeCall;
}

export async function startCall(destination: string) {
  if (!device) {
    throw new Error("Voice device not initialized");
  }

  activeCall = await device.connect({
    params: { to: destination }
  });

  return activeCall;
}

export function hangupCall() {
  if (activeCall) {
    activeCall.disconnect();
    activeCall = null;
  }
}

export function muteCall() {
  if (activeCall) activeCall.mute(true);
}

export function unmuteCall() {
  if (activeCall) activeCall.mute(false);
}
