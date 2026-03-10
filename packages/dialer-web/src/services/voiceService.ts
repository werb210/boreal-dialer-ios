import { Device, Call } from "@twilio/voice-sdk";

let device: Device | null = null;

export async function initializeVoice(identity: string) {

  const res = await fetch("/api/telephony/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ identity })
  });

  const data = await res.json();

  device = new Device(data.token, {
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
