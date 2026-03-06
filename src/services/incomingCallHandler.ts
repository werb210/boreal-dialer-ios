import type { Call, Device } from "@twilio/voice-sdk";
import { setCallStatus, setIncomingCall } from "../telephony/state/callStore";

export function handleIncomingCall(call: Call) {
  setIncomingCall(call);
  setCallStatus("incoming");
}

export function registerIncomingCallHandler(device: Device) {
  device.on("incoming", handleIncomingCall);
}
