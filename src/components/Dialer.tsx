import { useState } from "react";
import { makeCall } from "../services/voiceService";

export default function Dialer() {

  const [number, setNumber] = useState("");

  const handleCall = async () => {
    await makeCall(number);
  };

  return (
    <div style={{ padding: 20 }}>
      <h2>Dialer</h2>

      <input
        value={number}
        onChange={(e) => setNumber(e.target.value)}
        placeholder="Enter number"
        style={{
          width: "100%",
          padding: "10px",
          marginBottom: "10px"
        }}
      />

      <button onClick={handleCall}>
        Call
      </button>
    </div>
  );
}
