// BOREAL_DIALER_QUICK_CALL_STAFF_v149
import { useEffect, useState } from "react";
import {
  fetchQuickCall,
  pinnedStaff,
  startInternalCall,
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

  useEffect(() => {
    let alive = true;
    fetchQuickCall()
      .then((loaded) => { if (alive) setData(loaded); })
      // The dialer stays fully usable without quick call.
      .catch(() => undefined);
    return () => { alive = false; };
  }, []);

  const staff = pinnedStaff(data);
  if (staff.length === 0) return null;

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
    </div>
  );
}
