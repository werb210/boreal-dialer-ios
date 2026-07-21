import { FormEvent, useEffect, useMemo, useState } from "react";
import { getDialerAuthState, initializeDialerAuthState, login, logout } from "./auth/useDialerAuth";
import DialerScreen from "./telephony/components/DialerScreen";
import IncomingCallOverlay from "./telephony/components/IncomingCallOverlay";
import { startDialerSession } from "./telephony/services/voiceDevice";
import { setUiError } from "./telephony/state/callStore";

type TabId = "dial" | "contacts" | "sms" | "team";

const tabs: Array<{ id: TabId; label: string }> = [
  { id: "dial", label: "Dial" },
  { id: "contacts", label: "Contacts" },
  { id: "sms", label: "SMS" },
  { id: "team", label: "Team" }
];

const contacts = [
  { name: "Alex Morgan", phone: "+1 (415) 555-0110", tag: "Lead" },
  { name: "Riley Chen", phone: "+1 (650) 555-0184", tag: "Customer" },
  { name: "Jordan Lee", phone: "+1 (212) 555-0199", tag: "Support" }
];

const messages = [
  { from: "Maya", preview: "Can you send the quote after your next call?", time: "9:41 AM" },
  { from: "Ops", preview: "Reminder: update dispositions before EOD.", time: "10:12 AM" },
  { from: "Taylor", preview: "I left a voicemail and scheduled a callback.", time: "11:03 AM" }
];

const teammates = [
  { name: "Nina Patel", state: "Available" },
  { name: "Chris Fox", state: "On a call" },
  { name: "Sam Rivera", state: "Away" }
];

function LoginGate({ onAuthenticated }: { onAuthenticated: () => void }) {
  const [token, setToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const disabled = token.trim().length === 0;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    try {
      await login(token.trim());
      await startDialerSession();
      onAuthenticated();
    } catch (authError) {
      const message = authError instanceof Error ? authError.message : "Unable to sign in";
      setError(message);
    }
  }

  return (
    <main style={styles.centerShell}>
      <section style={styles.card} aria-labelledby="login-title">
        <p style={styles.eyebrow}>Boreal one-system dialer</p>
        <h1 id="login-title" style={styles.title}>Sign in to continue</h1>
        <p style={styles.copy}>Paste a valid portal auth token to unlock Dial, Contacts, SMS, and Team in one workspace.</p>
        <form onSubmit={handleSubmit} style={styles.form}>
          <label htmlFor="auth-token" style={styles.label}>Auth token</label>
          <textarea
            id="auth-token"
            value={token}
            onChange={(event) => setToken(event.target.value)}
            placeholder="eyJhbGciOi..."
            rows={5}
            style={styles.textarea}
          />
          {error ? <div role="alert" style={styles.error}>Login failed: {error}</div> : null}
          <button type="submit" disabled={disabled} style={{ ...styles.primaryButton, opacity: disabled ? 0.55 : 1 }}>
            Enter dialer
          </button>
        </form>
      </section>
    </main>
  );
}

function ContactsPanel() {
  return <ListPanel title="Contacts" items={contacts.map((contact) => `${contact.name} — ${contact.phone} · ${contact.tag}`)} />;
}

function SmsPanel() {
  return <ListPanel title="SMS" items={messages.map((message) => `${message.from}: ${message.preview} · ${message.time}`)} />;
}

function TeamPanel() {
  return <ListPanel title="Team" items={teammates.map((teammate) => `${teammate.name} — ${teammate.state}`)} />;
}

function ListPanel({ title, items }: { title: string; items: string[] }) {
  return (
    <section style={styles.panel} aria-labelledby={`${title.toLowerCase()}-title`}>
      <h2 id={`${title.toLowerCase()}-title`} style={styles.panelTitle}>{title}</h2>
      <ul style={styles.list}>{items.map((item) => <li key={item} style={styles.listItem}>{item}</li>)}</ul>
    </section>
  );
}

function Workspace({ onLogout }: { onLogout: () => void }) {
  const [activeTab, setActiveTab] = useState<TabId>("dial");
  const activeLabel = useMemo(() => tabs.find((tab) => tab.id === activeTab)?.label ?? "Dial", [activeTab]);

  return (
    <main style={styles.shell}>
      <header style={styles.header}>
        <div>
          <p style={styles.eyebrow}>One system</p>
          <h1 style={styles.title}>Boreal Dialer</h1>
        </div>
        <button type="button" onClick={onLogout} style={styles.secondaryButton}>Log out</button>
      </header>
      <nav aria-label="Dialer sections" style={styles.tabs}>
        {tabs.map((tab) => (
          <button key={tab.id} type="button" onClick={() => setActiveTab(tab.id)} aria-current={activeTab === tab.id ? "page" : undefined} style={activeTab === tab.id ? styles.activeTab : styles.tab}>
            {tab.label}
          </button>
        ))}
      </nav>
      <div aria-live="polite" style={styles.activeLabel}>Viewing {activeLabel}</div>
      {activeTab === "dial" ? <><IncomingCallOverlay /><DialerScreen /></> : null}
      {activeTab === "contacts" ? <ContactsPanel /> : null}
      {activeTab === "sms" ? <SmsPanel /> : null}
      {activeTab === "team" ? <TeamPanel /> : null}
    </main>
  );
}

export default function App() {
  const [ready, setReady] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    initializeDialerAuthState()
      .then(() => {
        const hasToken = Boolean(getDialerAuthState().token);
        setAuthenticated(hasToken);
        setReady(true);
        if (hasToken) {
          return startDialerSession();
        }
      })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : "Unknown error";
        setUiError(`Telephony initialization failed: ${message}`);
        setAuthenticated(false);
        setReady(true);
      });
  }, []);

  function handleLogout() {
    logout();
    setAuthenticated(false);
  }

  if (!ready) {
    return <main style={styles.centerShell}>Loading dialer…</main>;
  }

  return authenticated ? <Workspace onLogout={handleLogout} /> : <LoginGate onAuthenticated={() => setAuthenticated(true)} />;
}

const styles: Record<string, React.CSSProperties> = {
  shell: { maxWidth: 960, margin: "0 auto", padding: 24, fontFamily: "Inter, system-ui, sans-serif", color: "#102033" },
  centerShell: { minHeight: "100vh", display: "grid", placeItems: "center", padding: 24, fontFamily: "Inter, system-ui, sans-serif", background: "#f4f7fb", color: "#102033" },
  card: { width: "min(100%, 480px)", background: "white", borderRadius: 20, padding: 28, boxShadow: "0 24px 80px rgba(16, 32, 51, 0.14)" },
  header: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16, marginBottom: 20 },
  eyebrow: { margin: 0, color: "#4f6f94", fontSize: 13, fontWeight: 700, letterSpacing: 1.2, textTransform: "uppercase" },
  title: { margin: "4px 0 8px", fontSize: 32, lineHeight: 1.1 },
  copy: { margin: "0 0 20px", color: "#526476" },
  form: { display: "grid", gap: 12 },
  label: { fontWeight: 700 },
  textarea: { border: "1px solid #c8d3df", borderRadius: 12, padding: 12, font: "inherit", resize: "vertical" },
  error: { color: "#b42318", background: "#fff1f0", borderRadius: 10, padding: 10 },
  primaryButton: { border: 0, borderRadius: 999, padding: "12px 18px", background: "#0c66e4", color: "white", fontWeight: 800, cursor: "pointer" },
  secondaryButton: { border: "1px solid #c8d3df", borderRadius: 999, padding: "10px 16px", background: "white", color: "#102033", fontWeight: 700, cursor: "pointer" },
  tabs: { display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 8, marginBottom: 14 },
  tab: { border: "1px solid #c8d3df", borderRadius: 14, padding: 12, background: "white", cursor: "pointer", fontWeight: 700 },
  activeTab: { border: "1px solid #0c66e4", borderRadius: 14, padding: 12, background: "#eaf2ff", color: "#0649a8", cursor: "pointer", fontWeight: 800 },
  activeLabel: { marginBottom: 16, color: "#526476" },
  panel: { border: "1px solid #d8e0ea", borderRadius: 18, padding: 20, background: "#fff" },
  panelTitle: { marginTop: 0 },
  list: { display: "grid", gap: 10, padding: 0, margin: 0, listStyle: "none" },
  listItem: { padding: 14, borderRadius: 12, background: "#f4f7fb" }
};
