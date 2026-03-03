import { hangupCall, muteCall, unmuteCall } from "../services/voiceDevice";

export default function CallControls() {
  return (
    <div style={{ marginTop: 20 }}>
      <button onClick={muteCall}>Mute</button>
      <button onClick={unmuteCall}>Unmute</button>
      <button onClick={hangupCall}>Hang Up</button>
    </div>
  );
}
