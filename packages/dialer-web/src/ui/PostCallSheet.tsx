// BOREAL_DIALER_DISPOSITION_v154
import { useEffect, useState } from "react";
import { fetchDispositions, saveDisposition, confirmationFor, type Disposition } from "../lib/disposition";
type Props = { callId: string; contactName: string; onDone: () => void };
export default function PostCallSheet({ callId, contactName, onDone }: Props) {
  const [options, setOptions] = useState<Disposition[]>([]); const [busy, setBusy] = useState(false); const [message, setMessage] = useState<string | null>(null);
  useEffect(() => { let alive = true; fetchDispositions().then((loaded) => { if (alive) setOptions(loaded); }).catch(() => undefined); return () => { alive = false; }; }, []);
  const choose = async (option: Disposition) => { setBusy(true); const result = await saveDisposition(callId, option.id); setBusy(false); if (!result.ok) { setMessage("Could not save that outcome. Try again."); return; } setMessage(confirmationFor(option.id, Boolean(result.followUpCreated))); setTimeout(onDone, 1200); };
  return <div className="bd-postcall" role="dialog" aria-label="Call outcome"><h3 className="bd-postcall-title">How did the call with {contactName} go?</h3>{message ? <p className="bd-postcall-msg" role="status">{message}</p> : null}<div className="bd-postcall-opts">{options.map((option) => <button key={option.id} type="button" className="bd-postcall-opt" disabled={busy} onClick={() => void choose(option)}><span>{option.label}</span>{option.hint ? <small>{option.hint}</small> : null}</button>)}</div><button type="button" className="bd-postcall-skip" onClick={onDone} disabled={busy}>Skip</button></div>;
}
