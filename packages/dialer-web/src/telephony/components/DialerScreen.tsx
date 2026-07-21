import DialPad from "./DialPad";
import CallControls from "./CallControls";
import { useCallStore } from "../state/callStore";

export default function DialerScreen() {
  const { networkBanner, callStatus, uiError } = useCallStore();
  return <div>{networkBanner ? <div className="bd-banner">{networkBanner}</div> : null}{uiError ? <div className="bd-error">{uiError}</div> : null}<DialPad />{callStatus && callStatus !== "idle" ? <div className="bd-banner">Status: {callStatus}</div> : null}<div className="bd-section"><CallControls /></div></div>;
}
