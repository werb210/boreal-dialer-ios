import { api } from "../network/api";

type CallLogPayload = {
  direction: "inbound" | "outbound";
  from: string;
  to: string;
  startedAt: string;
  endedAt: string;
  duration: number;
  clientId?: string | null;
};

const queuedLogs: CallLogPayload[] = [];
let flushing = false;

async function postCallLog(payload: CallLogPayload): Promise<void> {
  await api.post("/api/calls/log", {
    direction: payload.direction,
    from: payload.from,
    to: payload.to,
    startedAt: payload.startedAt,
    endedAt: payload.endedAt,
    duration: payload.duration
  });
}

async function flushQueuedLogs() {
  if (flushing || queuedLogs.length === 0) {
    return;
  }

  flushing = true;

  try {
    while (queuedLogs.length > 0) {
      const next = queuedLogs[0];
      await postCallLog(next);
      queuedLogs.shift();
    }
  } finally {
    flushing = false;
  }
}

if (typeof window !== "undefined") {
  window.addEventListener("online", () => {
    void flushQueuedLogs();
  });
}

export async function logCall(payload: CallLogPayload): Promise<void> {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    queuedLogs.push(payload);
    return;
  }

  try {
    await postCallLog(payload);
  } catch (error) {
    queuedLogs.push(payload);
    throw error;
  }
}

export function __getQueuedCallLogsForTests() {
  return queuedLogs;
}
