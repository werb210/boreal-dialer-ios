import type { Device } from "@twilio/voice-sdk";
import { getDevice } from "../services/voiceDevice";

export function requireDevice(): Device {
  const device = getDevice();

  if (!device) {
    throw new Error("Twilio device not initialized");
  }

  return device;
}
