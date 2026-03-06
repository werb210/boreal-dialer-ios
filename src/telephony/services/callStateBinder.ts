import type { Call } from "@twilio/voice-sdk";
import { setCallState } from "../state/callState";

export function bindCallEvents(call: Call): void {
  call.on("ringing", () => setCallState("ringing"));
  call.on("accept", () => setCallState("in-call"));
  call.on("disconnect", () => setCallState("ended"));
  call.on("cancel", () => setCallState("ended"));
}
