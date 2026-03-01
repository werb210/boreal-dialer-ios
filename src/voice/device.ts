import { Device } from "@twilio/voice-sdk";

let device: Device | null = null;

export function getDevice(token: string) {
  if (device) return device;

  device = new Device(token, {
    codecPreferences: ["opus", "pcmu"],
    closeProtection: true,
    enableRingingState: true
  });

  return device;
}

export function destroyDevice() {
  if (device) {
    device.destroy();
    device = null;
  }
}
