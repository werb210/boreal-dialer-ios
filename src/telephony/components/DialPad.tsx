import { useState } from "react";
import { startCall } from "../services/voiceDevice";

export default function DialPad() {
  const [number, setNumber] = useState("");

  const call = async () => {
    if (!number) return;
    await startCall(number);
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

      <button onClick={call}>Call</button>
    </div>
  );
}
