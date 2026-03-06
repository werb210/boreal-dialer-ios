import { useEffect, useState } from "react";

export type CallState =
  | "idle"
  | "ringing"
  | "connecting"
  | "in-call"
  | "ended";

export function useCallState() {
  const [state, setState] = useState<CallState>("idle");

  useEffect(() => {
    const handleOffline = () => {
      if (!navigator.onLine) {
        setState((previous) => (previous === "in-call" ? "connecting" : previous));
      }
    };

    const handleOnline = () => {
      if (navigator.onLine) {
        setState((previous) => (previous === "connecting" ? "idle" : previous));
      }
    };

    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);

    return () => {
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener("online", handleOnline);
    };
  }, []);

  return {
    state,
    setState
  };
}
