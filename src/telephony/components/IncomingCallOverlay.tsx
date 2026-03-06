import { answerIncomingCall, rejectIncomingCall } from "../services/voiceDevice";
import { useCallStore } from "../state/callStore";

function getCallerIdentifier(from: unknown) {
  return typeof from === "string" && from.length > 0 ? from : "Unknown";
}

function getClientName(from: string) {
  if (from.startsWith("client:")) {
    return `Client ${from.replace("client:", "")}`;
  }

  return "Unknown client";
}

export default function IncomingCallOverlay() {
  const { incomingCall } = useCallStore();

  if (!incomingCall) {
    return null;
  }

  const caller = getCallerIdentifier(incomingCall.parameters.From);
  const clientName = getClientName(caller);

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
        <p>{clientName}</p>
        <div style={{ display: "flex", justifyContent: "center", gap: 12 }}>
          <button onClick={answerIncomingCall}>Accept</button>
          <button onClick={rejectIncomingCall}>Reject</button>
        </div>
      </div>
    </div>
  );
}
