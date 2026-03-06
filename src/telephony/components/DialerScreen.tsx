import DialPad from "./DialPad";
import CallControls from "./CallControls";
import { useCallStore } from "../state/callStore";

export default function DialerScreen() {
  const { networkBanner, callDuration, callStatus } = useCallStore();

  return (
    <div>
      {networkBanner ? <div>{networkBanner}</div> : null}
      <div>Status: {callStatus}</div>
      <div>Duration: {callDuration}s</div>
      <DialPad />
      <CallControls />
    </div>
  );
}
