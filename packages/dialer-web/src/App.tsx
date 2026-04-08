import { useEffect } from "react";
import { initializeDialerAuthState } from "./auth/useDialerAuth";
import DialerScreen from "./telephony/components/DialerScreen";
import IncomingCallOverlay from "./telephony/components/IncomingCallOverlay";
import { startDialerSession } from "./telephony/services/voiceDevice";
import { setUiError } from "./telephony/state/callStore";

export default function App() {
  useEffect(() => {
    initializeDialerAuthState()
      .then(() => startDialerSession())
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : "Unknown error";
        setUiError(`Telephony initialization failed: ${message}`);
      });
  }, []);

  return (
    <>
      <IncomingCallOverlay />
      <DialerScreen />
    </>
  );
}
