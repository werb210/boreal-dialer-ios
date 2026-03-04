import { Device, Call } from "@twilio/voice-sdk";

let device: Device | null = null;
let activeCall: Call | null = null;

export function registerVoiceDevice(token: string) {
  if (device) {
    device.destroy();
  }

  device = new Device(token);

  device.on("incoming", (call: Call) => {
    activeCall = call;

    call.on("disconnect", () => {
      activeCall = null;
    });

    call.accept();
  });

  device.on("error", (error: Error) => {
    throw new Error(`Twilio device error: ${error.message}`);
  });
}

export async function initializeVoice(token: string) {
  registerVoiceDevice(token);
}

export function startCall(to: string) {
  if (!device) {
    throw new Error("Device not initialized");
  }

  activeCall = device.connect({ params: { To: to } });
}

export function hangupCall() {
  if (activeCall) {
    activeCall.disconnect();
    activeCall = null;
  }
}

export function muteCall() {
  activeCall?.mute(true);
}

export function unmuteCall() {
  activeCall?.mute(false);
}
