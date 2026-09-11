// BOREAL_DIALER_QUICK_CALL_STAFF_v149
import { useEffect, useState } from "react";
import {
  fetchQuickCall,
  pinnedStaff,
  startInternalCall,
  saveQuickCallSlots,
  withSlot,
  QUICK_CALL_SLOTS,
  displayNameOf,
  initialsOf,
  isCallable,
  type QuickCallData,
  type QuickCallStaff,
} from "../lib/quickCall";
import { setUiError } from "../telephony/state/callStore";

export default function QuickCallRail() {
  const [data, setData] = useState<QuickCallData | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    let alive = true;
    fetchQuickCall()
      .then((loaded) => { if (alive) setData(loaded); })
      // The dialer stays fully usable without quick call.
      .catch(() => undefined);
    return () => { alive = false; };
  }, []);

  const staff = pinnedStaff(data);
  const pick = async (index: number, userId: string) => {
    if (!data) return;
    const slots = withSlot(data.slots, index, userId || null);
    setData({ ...data, slots });
    await saveQuickCallSlots(slots);
  };
  if (editing && data) return <div className="bd-rail-edit">
    {Array.from({ length: QUICK_CALL_SLOTS }).map((_, index) => <select key={index} className="bd-qc-select" value={data.slots[index] ?? ""} onChange={(event) => void pick(index, event.target.value)}><option value="">Empty</option>{data.staff.map((member) => <option key={member.user_id} value={member.user_id}>{displayNameOf(member)}</option>)}</select>)}
    <button type="button" className="bd-qc-done" onClick={() => setEditing(false)}>Done</button>
  </div>;
  if (staff.length === 0) return data ? <div className="bd-rail-empty"><button type="button" className="bd-qc-edit" onClick={() => setEditing(true)}>Pin staff for quick call</button></div> : null;

  const ring = async (member: QuickCallStaff) => {
    setBusy(member.user_id);
    const result = await startInternalCall(member);
    setBusy(null);
    if (!result.ok) {
      setUiError(
        result.error === "staff_not_reachable"
          ? `${displayNameOf(member)} is not signed in to the dialer.`
          : `Could not reach ${displayNameOf(member)}.`,
      );
    }
  };

  return (
    <div className="bd-rail" aria-label="Quick call staff">
      {staff.map((member) => (
        <button
          key={member.user_id}
          className="bd-qc"
          onClick={() => void ring(member)}
          disabled={busy !== null || !isCallable(member)}
          title={isCallable(member) ? displayNameOf(member) : `${displayNameOf(member)} is offline`}
        >
          <span className={`bd-av${member.online ? " is-online" : ""}`}>
            {initialsOf(member.name, member.email)}
          </span>
          <span className="bd-lbl">{displayNameOf(member)}</span>
        </button>
      ))}
      <button type="button" className="bd-qc-edit" onClick={() => setEditing(true)}>Edit</button>
    </div>
  );
}
