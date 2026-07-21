import { useEffect, useMemo, useState } from "react";
import DialerScreen from "../telephony/components/DialerScreen";
import { fetchRecentCalls, recentCallPhone, recentCallWhen, type RecentCall } from "../lib/apiClient";
import { setDialPrefill } from "../state/dialPrefill";

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export default function CallsTab() {
  const [calls, setCalls] = useState<RecentCall[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const load = () => { setLoading(true); setError(null); fetchRecentCalls().then(setCalls).catch((caught: unknown) => setError(caught instanceof Error ? caught.message : "Failed to load calls")).finally(() => setLoading(false)); };
  useEffect(() => { load(); }, []);
  const quickCall = useMemo(() => { const seen = new Set<string>(); const out: Array<{ name: string; phone: string }> = []; for (const call of calls) { const phone = recentCallPhone(call); const name = call.contact_name || phone; if (!phone || seen.has(phone)) continue; seen.add(phone); out.push({ name, phone }); if (out.length >= 8) break; } return out; }, [calls]);
  return <div>{quickCall.length > 0 ? <div className="bd-rail">{quickCall.map((entry) => <button key={entry.phone} className="bd-qc" onClick={() => setDialPrefill(entry.phone)}><span className="bd-av">{initials(entry.name)}</span><span className="bd-lbl">{entry.name}</span></button>)}</div> : null}<DialerScreen /><div className="bd-section"><div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}><h3 className="bd-h3">Recent calls</h3><button className="bd-btn" onClick={load}>Refresh</button></div>{loading ? <p className="bd-muted">Loading...</p> : null}{error ? <p style={{ color: "var(--red)" }}>{error}</p> : null}{!loading && calls.length === 0 ? <p className="bd-muted">No recent calls.</p> : null}<ul className="bd-list">{calls.map((call, index) => <li key={call.id ?? index} className="bd-li"><div><div className="bd-nm">{call.contact_name || recentCallPhone(call) || "Unknown"}</div><div className="bd-sub">{[call.direction === "inbound" ? "In" : "Out", call.duration_seconds ? `${call.duration_seconds}s` : null, recentCallWhen(call)].filter(Boolean).join("  -  ")}</div></div>{recentCallPhone(call) ? <button className="bd-btn" onClick={() => setDialPrefill(recentCallPhone(call))}>Dial</button> : null}</li>)}</ul></div></div>;
}
