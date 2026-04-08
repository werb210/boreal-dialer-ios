import { Device, Call } from "@twilio/voice-sdk";
import { getTwilioToken } from "./twilioTokenService";

let device: Device | null = null;

export async function initializeVoice() {
  const { token } = await getTwilioToken();

  device = new Device(token, {
    codecPreferences: [Call.Codec.Opus, Call.Codec.PCMU]
  });

  device.on("incoming", (call: Call) => {
    call.accept();
  });

  device.register();
}

export function getDevice() {
  return device;
}

export async function makeCall(to: string) {
  if (!device) {
    throw new Error("Device not initialized");
  }

  return device.connect({
    params: { to }
  });
}
