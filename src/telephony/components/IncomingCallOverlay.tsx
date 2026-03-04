import { answerIncomingCall, rejectIncomingCall } from "../services/voiceDevice";
import { useCallStore } from "../state/callStore";

function getCallerIdentifier(from: unknown) {
  return typeof from === "string" && from.length > 0 ? from : "Unknown";
}

export default function IncomingCallOverlay() {
  const { incomingCall } = useCallStore();

  if (!incomingCall) {
    return null;
  }

  const caller = getCallerIdentifier(incomingCall.parameters.From);

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        backgroundColor: "rgba(0, 0, 0, 0.6)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 9999
      }}
    >
      <div
        style={{
          minWidth: 280,
          backgroundColor: "white",
          borderRadius: 12,
          padding: 20,
          textAlign: "center"
        }}
      >
        <h2 style={{ marginTop: 0 }}>Incoming call</h2>
        <p>{caller}</p>
        <div style={{ display: "flex", justifyContent: "center", gap: 12 }}>
          <button onClick={answerIncomingCall}>Answer</button>
          <button onClick={rejectIncomingCall}>Decline</button>
        </div>
      </div>
    </div>
  );
}
