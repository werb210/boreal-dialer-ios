import type { Call, Device } from "@twilio/voice-sdk";
import { setCallStatus, setIncomingCall } from "../telephony/state/callStore";

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
