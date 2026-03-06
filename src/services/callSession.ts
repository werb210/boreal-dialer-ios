import type { Call } from "@twilio/voice-sdk";
import {
  clearAllCalls,
  clearIncomingCall,
  getCallStoreState,
  setActiveCall,
  setCallDuration,
  setCallStatus
} from "../telephony/state/callStore";

let callTimer: ReturnType<typeof setInterval> | null = null;

function stopTimer() {
  if (callTimer) {
    clearInterval(callTimer);
    callTimer = null;
  }
}

function startTimer() {
  stopTimer();
  setCallDuration(0);
  callTimer = setInterval(() => {
    const { callDuration } = getCallStoreState();
    setCallDuration(callDuration + 1);
  }, 1000);
}

export function cleanupCall(call?: Call) {
  stopTimer();
  const { activeCall, incomingCall } = getCallStoreState();
  if (!call || call === activeCall || call === incomingCall) {
    clearAllCalls();
    clearIncomingCall();
    setCallStatus("ended");
  }
}

export function bindCallSession(call: Call) {
  call.on("accept", () => {
    setActiveCall(call);
    clearIncomingCall();
    setCallStatus("in-call");
    startTimer();
  });

  call.on("disconnect", () => cleanupCall(call));
  call.on("cancel", () => cleanupCall(call));
  call.on("reject", () => cleanupCall(call));
  call.on("error", () => {
    cleanupCall(call);
  });
}
