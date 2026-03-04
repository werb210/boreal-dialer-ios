import { Device } from "@twilio/voice-sdk";

let device: Device | null = null;
let activeCall: any = null;

export async function initializeVoice(token: string) {
  device = new Device(token, {
    enableRingingState: true
  });

  device.on("registered", () => {});

  device.on("incoming", call => {
    activeCall = call;

    call.accept();
  });

  device.on("disconnect", () => {
    activeCall = null;
  });

  await device.register();
}

export function startCall(number: string) {
  if (!device) return;

  activeCall = device.connect({
    params: { To: number }
  });
}

export function hangupCall() {
  if (activeCall) {
    activeCall.disconnect();
    activeCall = null;
  }
}

export function muteCall() {
  if (activeCall) {
    activeCall.mute(true);
  }
}

export function unmuteCall() {
  if (activeCall) {
    activeCall.mute(false);
  }
}
