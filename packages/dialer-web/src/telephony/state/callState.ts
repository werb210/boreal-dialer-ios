export type CallStatus = "idle" | "dialing" | "ringing" | "in-call" | "ended";

let currentState: CallStatus = "idle";

export function getCallState(): CallStatus {
  return currentState;
}

export function setCallState(state: CallStatus): void {
  currentState = state;
}
