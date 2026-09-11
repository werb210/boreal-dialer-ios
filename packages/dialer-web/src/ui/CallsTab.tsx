// BOREAL_DIALER_QUICK_CALL_STAFF_v149 - the rail here used to be built from
// recent PSTN call history, so "quick call" meant recent customers in the
// dialer and pinned staff in the portal. It is staff on both now, and staff
// calls route internally rather than being logged as customer activity.
import { useEffect, useState } from "react";
import DialerScreen from "../telephony/components/DialerScreen";
import { fetchRecentCalls, type RecentCall } from "../lib/apiClient";
import QuickCallRail from "./QuickCallRail";
import RecentsList from "./RecentsList";

export default function CallsTab() {
  const [calls, setCalls] = useState<RecentCall[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const load = () => { setLoading(true); setError(null); fetchRecentCalls().then(setCalls).catch((caught: unknown) => setError(caught instanceof Error ? caught.message : "Failed to load calls")).finally(() => setLoading(false)); };
  useEffect(() => { load(); }, []);
  return <div><QuickCallRail /><DialerScreen /><div className="bd-section"><div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}><h3 className="bd-h3">Recent calls</h3><button className="bd-btn" onClick={load}>Refresh</button></div>{loading ? <p className="bd-muted">Loading...</p> : null}{error ? <p style={{ color: "var(--red)" }}>{error}</p> : null}{!loading && calls.length === 0 ? <p className="bd-muted">No recent calls.</p> : null}<RecentsList calls={calls} /></div></div>;
}
