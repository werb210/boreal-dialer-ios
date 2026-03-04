import DialerScreen from "./telephony/components/DialerScreen";
import { initializeVoice } from "./telephony/services/voiceDevice";
import { fetchVoiceToken } from "./api/voice";

async function startVoice() {
  const token = await fetchVoiceToken("staff_mobile");

  await initializeVoice(token);
}

startVoice();

export default function App() {
  return <DialerScreen />;
}
