import { Device, Call } from "@twilio/voice-sdk";

let device: Device | null = null;
let activeCall: Call | null = null;
let incomingCall: Call | null = null;

export function registerVoiceDevice(token: string) {
  if (device) {
    device.destroy();
  }

  device = new Device(token);

  device.on("incoming", (call: Call) => {
    incomingCall = call;

    call.on("accept", () => {
      activeCall = call;
      incomingCall = null;
    });

    call.on("disconnect", () => {
      activeCall = null;
      incomingCall = null;
    });

    call.on("reject", () => {
      incomingCall = null;
    });
  });

  device.on("disconnect", () => {
    activeCall = null;
    incomingCall = null;
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

  activeCall = await device.connect({ params: { To: to } });
}

export function hangupCall() {
  if (activeCall) {
    activeCall.disconnect();
    activeCall = null;
  }
}

export function answerIncomingCall() {
  if (!incomingCall) return;

  incomingCall.accept();
  activeCall = incomingCall;
  incomingCall = null;
}

export function rejectIncomingCall() {
  if (!incomingCall) return;

  incomingCall.reject();
  incomingCall = null;
}

export function muteCall() {
  activeCall?.mute(true);
}

export function unmuteCall() {
  activeCall?.mute(false);
}
