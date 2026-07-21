import { useEffect, useState } from "react";
import { startDialerSession } from "../services/voiceDevice";
import { setUiError } from "../state/callStore";
import { getDialPrefill, subscribeDialPrefill } from "../../state/dialPrefill";

const KEYS: Array<{ d: string; s: string }> = [
  { d: "1", s: "" }, { d: "2", s: "ABC" }, { d: "3", s: "DEF" },
  { d: "4", s: "GHI" }, { d: "5", s: "JKL" }, { d: "6", s: "MNO" },
  { d: "7", s: "PQRS" }, { d: "8", s: "TUV" }, { d: "9", s: "WXYZ" },
  { d: "*", s: "" }, { d: "0", s: "+" }, { d: "#", s: "" }
];

export default function DialPad() {
  const [number, setNumber] = useState(getDialPrefill());
  useEffect(() => subscribeDialPrefill((value) => setNumber(value)), []);
  const press = (digit: string) => setNumber((current) => current + digit);
  const backspace = () => setNumber((current) => current.slice(0, -1));
  const clear = () => setNumber("");
  const handleDial = async () => {
    if (!number) return;
    try { await startDialerSession(number); setUiError(null); }
    catch (error) { const message = error instanceof Error ? error.message : "Unknown error"; setUiError(`Call start failed: ${message}`); }
  };
  return <div><div className="bd-kp-display"><div className="bd-kp-label">ENTER A NUMBER</div><div className="bd-kp-number">{number || "\u00A0"}</div></div><div className="bd-keypad">{KEYS.map((key) => <button key={key.d} className="bd-key" onClick={() => press(key.d)}>{key.d}{key.s ? <small>{key.s}</small> : null}</button>)}</div><div className="bd-callrow"><button className="side" onClick={backspace}>Delete</button><button className="bd-callbtn" onClick={handleDial} aria-label="Call">&#9742;</button><button className="side" onClick={clear}>Clear</button></div></div>;
}
