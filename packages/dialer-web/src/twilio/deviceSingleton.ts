import type { Device } from "@twilio/voice-sdk";

let device: Device | null = null;

export function setDevice(d: Device): void {
  device = d;
}

export function getDevice(): Device | null {
  return device;
}

export function clearDevice(): void {
  device = null;
}
