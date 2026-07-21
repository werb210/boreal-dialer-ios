import { useEffect, useState } from "react";
import { fetchContacts, contactName, contactPhone, type Contact } from "../lib/apiClient";
import { setDialPrefill } from "../state/dialPrefill";
import { setSelectedContact } from "../state/selectedContact";

export default function ContactsTab({ onNavigate }: { onNavigate: (tab: "calls" | "sms") => void }) {
  const [search, setSearch] = useState(""); const [contacts, setContacts] = useState<Contact[]>([]); const [error, setError] = useState<string | null>(null); const [loading, setLoading] = useState(false);
  const load = async (term: string) => { setLoading(true); setError(null); try { setContacts(await fetchContacts(term)); } catch (caught) { setError(caught instanceof Error ? caught.message : "Failed to load contacts"); } finally { setLoading(false); } };
  useEffect(() => { void load(""); }, []);
  const dial = (contact: Contact) => { setDialPrefill(contactPhone(contact)); onNavigate("calls"); };
  const text = (contact: Contact) => { setSelectedContact({ id: contact.id, name: contactName(contact), phone: contactPhone(contact) }); onNavigate("sms"); };
  return <div><div className="bd-search"><input className="bd-input" value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") void load(search); }} placeholder="Search contacts" /><button className="bd-btn" onClick={() => void load(search)}>Search</button></div>{loading ? <p className="bd-banner">Loading...</p> : null}{error ? <p style={{ color: "var(--red)", padding: "0 16px" }}>{error}</p> : null}{!loading && contacts.length === 0 ? <p className="bd-banner">No contacts.</p> : null}<ul className="bd-list">{contacts.map((contact) => <li key={contact.id} className="bd-li"><div><div className="bd-nm">{contactName(contact)}</div><div className="bd-sub">{contactPhone(contact) || "no phone"}</div></div><div className="bd-actions"><button className="bd-btn" onClick={() => dial(contact)} disabled={!contactPhone(contact)}>Dial</button><button className="bd-btn" onClick={() => text(contact)} disabled={!contactPhone(contact)}>Text</button></div></li>)}</ul></div>;
}
