import React, { useEffect } from "react";
import DialPad from "./DialPad";
import CallControls from "./CallControls";
import { initializeVoice } from "../services/voiceDevice";

export default function DialerScreen() {
  useEffect(() => {
    initializeVoice("staff_mobile");
  }, []);

  return (
    <div>
      <DialPad />
      <CallControls />
    </div>
  );
}
