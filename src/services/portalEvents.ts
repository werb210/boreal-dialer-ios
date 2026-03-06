let socket: WebSocket | null = null;

function getSocket() {
  if (typeof window === "undefined") {
    return null;
  }

  if (socket && socket.readyState <= WebSocket.OPEN) {
    return socket;
  }

  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  socket = new WebSocket(`${protocol}://${window.location.host}/ws/calls`);
  return socket;
}

export function emitPortalCallEvent(
  event: "call_started" | "call_answered" | "call_ended",
  payload: Record<string, unknown>
) {
  const activeSocket = getSocket();
  if (!activeSocket) {
    return;
  }

  const message = JSON.stringify({ event, payload });

  if (activeSocket.readyState === WebSocket.OPEN) {
    activeSocket.send(message);
    return;
  }

  activeSocket.addEventListener(
    "open",
    () => {
      activeSocket.send(message);
    },
    { once: true }
  );
}
