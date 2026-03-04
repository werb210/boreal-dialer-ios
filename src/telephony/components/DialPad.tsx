import { useState } from "react";
import { startCall } from "../services/voiceDevice";

export default function DialPad() {
  const [number, setNumber] = useState("");

  const handleDial = async () => {
    if (!number) return;

    try {
      await startCall(number);
    } catch (err) {
      console.error("Dial failed", err);
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
