import { Device, Call } from "@twilio/voice-sdk";

let device: Device | null = null;
let activeCall: Call | null = null;

export async function initializeVoice(token: string) {
  device = new Device(token, {
    codecPreferences: [Call.Codec.Opus, Call.Codec.PCMU],
    logLevel: 1
  });

  device.on("registered", () => {
    console.log("Twilio device registered");
  });

  device.on("incoming", (call: Call) => {
    activeCall = call;

    call.on("disconnect", () => {
      activeCall = null;
    });
  });

  await device.register();
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
    params: {
      To: destination
    }
  });

  activeCall.on("disconnect", () => {
    activeCall = null;
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
