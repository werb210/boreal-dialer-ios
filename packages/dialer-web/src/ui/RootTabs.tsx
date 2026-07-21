import { useState } from "react";
import CallsTab from "./CallsTab"; import ContactsTab from "./ContactsTab"; import MessagesTab from "./MessagesTab"; import SmsTab from "./SmsTab"; import TeamTab from "./TeamTab"; import CalendarTab from "./CalendarTab"; import { logout } from "../auth/useDialerAuth";
type TabKey = "calls" | "contacts" | "messages" | "sms" | "team" | "calendar";
const TABS: Array<{ key: TabKey; label: string }> = [{ key: "calls", label: "Calls" }, { key: "contacts", label: "Contacts" }, { key: "messages", label: "Messages" }, { key: "sms", label: "SMS" }, { key: "team", label: "Team" }, { key: "calendar", label: "Calendar" }];
export default function RootTabs({ onLogout }: { onLogout: () => void }) {
  const [tab, setTab] = useState<TabKey>("calls"); const handleLogout = () => { logout(); onLogout(); }; const goto = (next: "calls" | "sms") => setTab(next);
  return <div className="bd-app"><header className="bd-header"><strong>Boreal Dialer</strong><button className="bd-btn" onClick={handleLogout}>Log out</button></header><main className="bd-main">{tab === "calls" ? <CallsTab /> : null}{tab === "contacts" ? <ContactsTab onNavigate={goto} /> : null}{tab === "messages" ? <MessagesTab /> : null}{tab === "sms" ? <SmsTab /> : null}{tab === "team" ? <TeamTab /> : null}{tab === "calendar" ? <CalendarTab /> : null}</main><nav className="bd-tabbar">{TABS.map((entry) => <button key={entry.key} className={entry.key === tab ? "bd-tab active" : "bd-tab"} onClick={() => setTab(entry.key)}>{entry.label}</button>)}</nav></div>;
}
