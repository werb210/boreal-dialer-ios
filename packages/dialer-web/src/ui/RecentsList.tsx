// BOREAL_DIALER_RECENTS_v154
import { groupRecents, subtitleFor, type RecentRow } from "../lib/recents";
import type { RecentCall } from "../lib/apiClient";
import { setDialPrefill } from "../state/dialPrefill";

type Props = { calls: RecentCall[]; onOpen?: (row: RecentRow) => void };
export default function RecentsList({ calls, onOpen }: Props) {
  const groups = groupRecents(calls);
  if (groups.length === 0) return null;
  return <div className="bd-recents">{groups.map((group) => <section key={group.header}>
    <h4 className="bd-recents-day">{group.header}</h4>
    {group.rows.map((row) => <div key={row.key} className="bd-recent">
      <span className="bd-recent-av">{row.initials}</span>
      <button type="button" className="bd-recent-main" onClick={() => onOpen?.(row)} aria-label={`${row.name}, ${subtitleFor(row)}`}>
        <span className="bd-recent-name">{row.name}</span><span className="bd-recent-sub"><span className={`bd-arrow${row.inbound ? " in" : " out"}`} aria-hidden="true">{row.inbound ? "↙" : "↗"}</span>{subtitleFor(row)}</span>
      </button>
      {row.phone ? <button type="button" className="bd-recent-call" onClick={() => setDialPrefill(row.phone)} aria-label={`Call ${row.name}`}>☎</button> : null}
      <span className="bd-recent-chev" aria-hidden="true">›</span>
    </div>)}
  </section>)}</div>;
}
