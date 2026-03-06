import type { Call, Device } from "@twilio/voice-sdk";
import {
  setActiveCall,
  setCallStatus,
  setIncomingCall
} from "../telephony/state/callStore";

export function handleIncomingCall(call: Call) {
  setIncomingCall(call);
  setCallStatus("ringing");

  call.on("accept", () => {
    setActiveCall(call);
    setCallStatus("in-call");
  });

  call.on("disconnect", () => {
    setCallStatus("ended");
  });

  call.on("reject", () => {
    setCallStatus("ended");
  });
}

export function registerIncomingCallHandler(device: Device) {
  device.on("incoming", (call) => {
    handleIncomingCall(call);
  });
}
