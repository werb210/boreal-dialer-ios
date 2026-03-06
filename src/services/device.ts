import { Device } from "@twilio/voice-sdk";
import { getTwilioToken } from "./twilioTokenService";

let device: Device | null = null;

export async function getDevice(): Promise<Device> {
  if (device) {
    return device;
  }

  const { token } = await getTwilioToken();
  device = new Device(token, { logLevel: 1 });

  device.on("tokenWillExpire", async () => {
    const next = await getTwilioToken();
    await device?.updateToken(next.token);
  });

  return device;
}
