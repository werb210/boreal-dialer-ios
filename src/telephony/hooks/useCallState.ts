import { useState } from "react";

export type CallState =
  | "idle"
  | "ringing"
  | "connecting"
  | "connected"
  | "ended";

export function useCallState() {
  const [state, setState] = useState<CallState>("idle");

  return {
    state,
    setState
  };
}
