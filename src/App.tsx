import { useEffect } from "react";
import DialerScreen from "./telephony/components/DialerScreen";
import IncomingCallOverlay from "./telephony/components/IncomingCallOverlay";
import { initializeVoice } from "./telephony/services/voiceDevice";

export default function App() {
  useEffect(() => {
    void initializeVoice();
  }, []);

  return (
    <>
      <IncomingCallOverlay />
      <DialerScreen />
    </>
  );
}
