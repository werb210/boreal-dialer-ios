import type { Call, Device } from "@twilio/voice-sdk";
import { setCallStatus, setIncomingCall } from "../telephony/state/callStore";
import { getDevice } from "../telephony/services/voiceDevice";

export function handleIncomingCall(call: Call) {
  setIncomingCall(call);
  setCallStatus("ringing");

  call.on("accept", () => {
    setCallStatus("in-call");
  });

  call.on("disconnect", () => {
    setCallStatus("ended");
    setIncomingCall(null);
  });

  call.on("reject", () => {
    setCallStatus("ended");
    setIncomingCall(null);
  });
}

export function registerIncomingHandler(device: Device) {
  device.on("incoming", (call) => {
    handleIncomingCall(call);
  });
}

export function registerIncomingCallHandler(callback: (call: Call) => void) {
  const device = getDevice();

  if (!device) {
    throw new Error("Twilio device not initialized");
  }

  device.on("incoming", (call: Call) => {
    callback(call);
  });
}
