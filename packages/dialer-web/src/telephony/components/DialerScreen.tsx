import DialPad from "./DialPad";
import CallControls from "./CallControls";
import { useCallStore } from "../state/callStore";
// BOREAL_DIALER_POSTCALL_MOUNT_v161
import { useEffect, useState } from "react";
import PostCallSheet from "../../ui/PostCallSheet";
import { getEndedCall, subscribeEndedCall, clearEndedCall, type EndedCall } from "../../lib/lastCall";

export default function DialerScreen() {
  const { networkBanner, callStatus, uiError } = useCallStore();
  // BOREAL_DIALER_POSTCALL_MOUNT_v161
  const [ended, setEnded] = useState<EndedCall | null>(getEndedCall());
  useEffect(() => subscribeEndedCall(setEnded), []);
  return <div>{networkBanner ? <div className="bd-banner">{networkBanner}</div> : null}{uiError ? <div className="bd-error">{uiError}</div> : null}<DialPad />{callStatus && callStatus !== "idle" ? <div className="bd-banner">Status: {callStatus}</div> : null}<div className="bd-section"><CallControls /></div>{ended ? <PostCallSheet callId={ended.sid} contactName={ended.contactName} onDone={clearEndedCall} /> : null}</div>;
}
