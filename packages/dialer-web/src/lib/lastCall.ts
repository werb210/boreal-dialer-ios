// BOREAL_DIALER_POSTCALL_MOUNT_v161
// Remembers the call that just ended, so the post-call sheet knows what it is
// asking about.
//
// v154 built PostCallSheet and left it unmounted, because the dialer holds a
// Twilio CallSid and the disposition endpoint took our call_logs UUID.
// BF_SERVER_CALL_REF_v161 made that endpoint accept either, so a CallSid is now
// enough to record an outcome.

export type EndedCall = {
  /** Twilio CallSid. The server resolves it to its own call row. */
  sid: string;
  contactName: string;
  /** Outbound calls are the ones worth dispositioning; inbound too, but a
   *  rejected ring is not. */
  connected: boolean;
};

type Listener = (call: EndedCall | null) => void;

let current: EndedCall | null = null;
const listeners = new Set<Listener>();

export function getEndedCall(): EndedCall | null {
  return current;
}

export function subscribeEndedCall(listener: Listener): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

function emit(): void {
  for (const listener of [...listeners]) listener(current);
}

/** A Twilio CallSid; anything else cannot be dispositioned. */
export function isCallSid(raw: unknown): boolean {
  return /^CA[0-9a-f]{32}$/i.test(String(raw ?? "").trim());
}

/**
 * Records the call that just ended. A call that never connected is not offered
 * for disposition - "no answer" is already the outcome, and asking about every
 * misdial would make the sheet noise.
 */
export function noteCallEnded(input: {
  sid?: unknown;
  contactName?: unknown;
  connected?: boolean;
}): void {
  const sid = String(input.sid ?? "").trim();
  if (!isCallSid(sid) || input.connected !== true) {
    return;
  }
  current = {
    sid,
    contactName: String(input.contactName ?? "").trim() || "that call",
    connected: true,
  };
  emit();
}

/** Dismissed, or an outcome was recorded. */
export function clearEndedCall(): void {
  current = null;
  emit();
}
