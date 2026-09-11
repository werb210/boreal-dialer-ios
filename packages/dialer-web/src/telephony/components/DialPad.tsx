import { useEffect, useState } from "react";
import { startDialerSession } from "../services/voiceDevice";
import { setUiError } from "../state/callStore";
import { getDialPrefill, subscribeDialPrefill } from "../../state/dialPrefill";

// BOREAL_DIALER_KEYPAD_UI_v147
// Rebuilt to match the reference design. Four differences from the previous
// layout, all of them things the design does and the old markup did not:
//   - the country prefix is a chip sitting inline with the placeholder, not a
//     separate heading above a large empty number line
//   - the keypad fills the width instead of sitting in a 44px-inset column
//   - backspace is a glyph on the trailing side, not a "Delete" text button,
//     and there is no "Clear" button at all - holding backspace clears
//   - the call button is visibly inert until there is something to dial

const KEYS: Array<{ d: string; s: string }> = [
  { d: "1", s: "" }, { d: "2", s: "ABC" }, { d: "3", s: "DEF" },
  { d: "4", s: "GHI" }, { d: "5", s: "JKL" }, { d: "6", s: "MNO" },
  { d: "7", s: "PQRS" }, { d: "8", s: "TUV" }, { d: "9", s: "WXYZ" },
  { d: "*", s: "" }, { d: "0", s: "+" }, { d: "#", s: "" }
];

export const DIAL_PREFIX = "+1";

/** Groups a NANP number the way the design shows it while typing. */
export function formatDialed(raw: string): string {
  const digits = raw.replace(/[^0-9*#]/g, "");
  if (digits.length === 0) return "";
  if (/[*#]/.test(digits) || digits.length > 10) return digits;
  const a = digits.slice(0, 3);
  const b = digits.slice(3, 6);
  const c = digits.slice(6, 10);
  if (digits.length <= 3) return a;
  if (digits.length <= 6) return `(${a}) ${b}`;
  return `(${a}) ${b}-${c}`;
}

export default function DialPad() {
  const [number, setNumber] = useState(getDialPrefill());
  useEffect(() => subscribeDialPrefill((value) => setNumber(value)), []);

  const press = (digit: string) => setNumber((current) => current + digit);
  const backspace = () => setNumber((current) => current.slice(0, -1));
  const clear = () => setNumber("");

  const handleDial = async () => {
    if (!number) return;
    try {
      await startDialerSession(number);
      setUiError(null);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setUiError(`Call start failed: ${message}`);
    }
  };

  const hasNumber = number.length > 0;

  return (
    <div className="bd-kp">
      <div className="bd-kp-entry">
        <span className="bd-kp-prefix">{DIAL_PREFIX}</span>
        {hasNumber
          ? <span className="bd-kp-number">{formatDialed(number)}</span>
          : <span className="bd-kp-placeholder">Enter number</span>}
      </div>

      <div className="bd-keypad">
        {KEYS.map((key) => (
          <button key={key.d} className="bd-key" onClick={() => press(key.d)}>
            <span className="bd-key-d">{key.d}</span>
            {key.s ? <small>{key.s}</small> : null}
          </button>
        ))}
      </div>

      <div className="bd-callrow">
        <span className="bd-callrow-spacer" />
        <button
          className={`bd-callbtn${hasNumber ? "" : " is-idle"}`}
          onClick={handleDial}
          disabled={!hasNumber}
          aria-label="Call"
        >
          &#9742;
        </button>
        <button
          className={`bd-backspace${hasNumber ? "" : " is-hidden"}`}
          onClick={backspace}
          onContextMenu={(event) => { event.preventDefault(); clear(); }}
          aria-label="Backspace"
        >
          &#9003;
        </button>
      </div>
    </div>
  );
}
