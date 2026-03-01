let interval: NodeJS.Timeout | null = null;

export function startHeartbeat() {
  if (interval) return;

  interval = setInterval(() => {
    fetch("/api/voice/ping").catch(() => {});
  }, 15000);
}

export function stopHeartbeat() {
  if (interval) {
    clearInterval(interval);
    interval = null;
  }
}
