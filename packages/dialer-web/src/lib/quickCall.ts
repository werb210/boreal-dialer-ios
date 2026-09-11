// BOREAL_DIALER_QUICK_CALL_STAFF_v149
// Quick call is staff-to-staff, on every surface.
//
// The portal has always worked this way: QuickCallRow loads
// /api/telephony/quick-call and rings a colleague's browser through
// startInternalCall, which the server records as direction 'internal'.
//
// The dialer did something different under the same name - it built the rail
// from recent PSTN call history and prefilled a customer's number, which then
// dialled out through the normal path and was logged as an ordinary outbound
// call. This brings the dialer in line: same endpoint, same staff, same
// internal call path, and therefore not recorded as customer activity.
import { apiGet, apiPost } from "./apiClient";

export type QuickCallStaff = {
  user_id: string;
  name: string | null;
  email: string | null;
  profile_image_url?: string | null;
  identity: string | null;
  online?: boolean;
};

export type QuickCallData = {
  staff: QuickCallStaff[];
  /** The caller's saved picks, as staff user ids. */
  slots: string[];
};

export const QUICK_CALL_SLOTS = 3;

export function initialsOf(name: string | null | undefined, email?: string | null): string {
  const source = String(name ?? "").trim() || String(email ?? "").trim();
  if (!source) return "?";
  const parts = source.split(/\s+/).filter(Boolean);
  const first = parts[0] ?? "";
  if (parts.length === 1) return first.slice(0, 2).toUpperCase();
  const last = parts[parts.length - 1] ?? first;
  return ((first[0] ?? "") + (last[0] ?? "")).toUpperCase();
}

export function displayNameOf(staff: QuickCallStaff): string {
  const name = String(staff.name ?? "").trim();
  if (name) return name;
  const email = String(staff.email ?? "").trim();
  if (email) return email.split("@")[0] ?? email;
  return "Staff";
}

/** Resolves the caller's saved picks to staff records, preserving slot order. */
export function pinnedStaff(data: QuickCallData | null): QuickCallStaff[] {
  if (!data) return [];
  const byId = new Map(data.staff.map((s) => [s.user_id, s]));
  return data.slots
    .slice(0, QUICK_CALL_SLOTS)
    .map((id) => byId.get(id))
    .filter((s): s is QuickCallStaff => Boolean(s));
}

/**
 * A staff member is callable only once they hold a Twilio identity - that is
 * what dial.client() rings. Without one there is nothing to ring, so the
 * button would fail silently.
 */
export function isCallable(staff: QuickCallStaff): boolean {
  return Boolean(staff.identity);
}

export async function fetchQuickCall(): Promise<QuickCallData> {
  const raw = await apiGet<any>("/api/telephony/quick-call");
  const data = raw?.data ?? raw;
  return {
    staff: Array.isArray(data?.staff) ? data.staff : [],
    slots: Array.isArray(data?.slots) ? data.slots.slice(0, QUICK_CALL_SLOTS) : [],
  };
}

export type StartInternalCallResult = { ok: boolean; conferenceFriendly?: string; error?: string };

/**
 * Rings a colleague. Goes to /api/voice/calls with staffIdentity, which the
 * server classifies as an internal conference rather than a customer call.
 */
export async function startInternalCall(
  staff: QuickCallStaff,
): Promise<StartInternalCallResult> {
  if (!isCallable(staff)) return { ok: false, error: "staff_not_reachable" };
  try {
    const raw = await apiPost<any>("/api/voice/calls", {
      staffIdentity: staff.identity,
      contactName: displayNameOf(staff),
    });
    const body = raw?.data ?? raw;
    if (!body?.ok) return { ok: false, error: body?.error ?? "call_setup_failed" };
    return { ok: true, conferenceFriendly: body.conferenceFriendly };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : "call_setup_failed" };
  }
}


// BOREAL_DIALER_QUICK_CALL_EDIT_v154
export async function saveQuickCallSlots(slots: string[]): Promise<boolean> {
  try {
    const raw = await apiPost<any>("/api/telephony/quick-call", { slots: slots.filter(Boolean).slice(0, QUICK_CALL_SLOTS) });
    const body = raw?.data ?? raw;
    return body?.ok !== false;
  } catch { return false; }
}

export function withSlot(slots: string[], index: number, userId: string | null): string[] {
  const next = slots.slice(0, QUICK_CALL_SLOTS);
  while (next.length < QUICK_CALL_SLOTS) next.push("");
  if (userId) for (let i = 0; i < next.length; i += 1) if (i !== index && next[i] === userId) next[i] = "";
  next[index] = userId ?? "";
  return next;
}
