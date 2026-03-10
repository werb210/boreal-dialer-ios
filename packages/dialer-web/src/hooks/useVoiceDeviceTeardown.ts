import { useEffect } from "react";
import { destroyDevice } from "../voice/device";

export function useVoiceDeviceTeardown() {
  useEffect(() => {
    return () => {
      destroyDevice();
    };
  }, []);
}
