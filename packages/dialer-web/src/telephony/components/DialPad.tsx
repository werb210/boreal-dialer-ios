import { useState } from "react";
import { startDialerSession } from "../services/voiceDevice";
import { setUiError } from "../state/callStore";

export default function DialPad() {
  const [number, setNumber] = useState("");

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

  return (
    <div style={{ padding: 20 }}>
      <h2>Dial</h2>

      <input
        value={number}
        onChange={(e) => setNumber(e.target.value)}
        placeholder="Phone number"
        style={{
          width: "100%",
          padding: 10,
          marginBottom: 10
        }}
      />

      <button onClick={handleDial}>Call</button>
    </div>
  );
}
