export type CallStatus =
  | "idle"
  | "incoming"
  | "connecting"
  | "connected"
  | "ended";

let currentStatus: CallStatus = "idle";

export function setCallStatus(status: CallStatus) {
  currentStatus = status;
}

export function getCallStatus(): CallStatus {
  return currentStatus;
}
