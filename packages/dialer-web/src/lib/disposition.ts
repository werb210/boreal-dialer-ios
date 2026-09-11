// BOREAL_DIALER_DISPOSITION_v154
import { apiGet, apiPost } from "./apiClient";
export type Disposition = { id: string; label: string; createsTask: boolean; hint?: string };
export const DISPOSITION_LABELS: Record<string, { label: string; createsTask: boolean; hint?: string }> = {
  connected: { label: "Connected", createsTask: false }, documents_promised: { label: "Documents promised", createsTask: true, hint: "Task in 3 days" }, follow_up: { label: "Follow-up required", createsTask: true, hint: "Task in 2 days" }, needs_lender_review: { label: "Needs lender review", createsTask: true, hint: "Task tomorrow" }, demo_booked: { label: "Demo booked", createsTask: true, hint: "Prep task tomorrow" }, left_voicemail: { label: "Left voicemail", createsTask: false }, no_answer: { label: "No answer", createsTask: false }, not_interested: { label: "Not interested", createsTask: false }, do_not_contact: { label: "Do not contact", createsTask: false, hint: "Stops outreach" },
};
const ORDER = ["connected", "documents_promised", "follow_up", "needs_lender_review", "demo_booked", "left_voicemail", "no_answer", "not_interested", "do_not_contact"];
export function toDispositions(ids: string[]): Disposition[] {
  return [...ORDER.filter((id) => ids.includes(id)), ...ids.filter((id) => !ORDER.includes(id))].map((id) => {
    const meta = DISPOSITION_LABELS[id];
    return { id, label: meta?.label ?? id.replace(/_/g, " "), createsTask: meta?.createsTask ?? false, ...(meta?.hint ? { hint: meta.hint } : {}) };
  });
}
export async function fetchDispositions(): Promise<Disposition[]> { const raw = await apiGet<any>("/api/telephony/dispositions"); const data = raw?.data ?? raw; return toDispositions(Array.isArray(data?.dispositions) ? data.dispositions : []); }
export type SaveResult = { ok: boolean; followUpCreated?: boolean; error?: string };
export async function saveDisposition(callId: string, disposition: string): Promise<SaveResult> {
  if (!callId) return { ok: false, error: "missing_call_id" };
  try { const raw = await apiPost<any>(`/api/telephony/calls/${encodeURIComponent(callId)}/disposition`, { disposition }); const body = raw?.data ?? raw; if (body?.success === false) return { ok: false, error: body?.error ?? "disposition_failed" }; const data = body?.data ?? body; return { ok: true, followUpCreated: Boolean(data?.followUpCreated) }; } catch (error) { return { ok: false, error: error instanceof Error ? error.message : "disposition_failed" }; }
}
export function confirmationFor(disposition: string, followUpCreated: boolean): string { const label = DISPOSITION_LABELS[disposition]?.label ?? disposition.replace(/_/g, " "); return followUpCreated ? `${label} — follow-up task created` : `${label} — saved`; }
