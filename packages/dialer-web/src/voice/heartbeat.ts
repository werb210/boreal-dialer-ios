import { api } from "../network/api";

let interval: NodeJS.Timeout | null = null;

export function startHeartbeat() {
  if (interval) return;

  interval = setInterval(() => {
    void api.post("/api/voice/ping");
  }, 15000);
}

export function stopHeartbeat() {
  if (interval) {
    clearInterval(interval);
    interval = null;
  }
}
