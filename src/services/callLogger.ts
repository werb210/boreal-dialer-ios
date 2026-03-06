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
  const response = await fetch("/api/calls/log", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      direction: payload.direction,
      from: payload.from,
      to: payload.to,
      startedAt: payload.startedAt,
      endedAt: payload.endedAt,
      duration: payload.duration
    })
  });

  if (!response.ok) {
    throw new Error(`Failed to log call: ${response.status}`);
  }
}

async function flushQueuedLogs() {
  if (flushing || queuedLogs.length === 0) {
    return;
  }

  flushing = true;

  while (queuedLogs.length > 0) {
    const next = queuedLogs[0];

    try {
      await postCallLog(next);
      queuedLogs.shift();
    } catch {
      break;
    }
  }

  flushing = false;
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
  } catch {
    queuedLogs.push(payload);
  }
}

export function __getQueuedCallLogsForTests() {
  return queuedLogs;
}
