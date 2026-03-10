import { useState } from "react";

export default function useCallState() {

  const [status, setStatus] = useState("idle");

  function setRinging() {
    setStatus("ringing");
  }

  function setConnected() {
    setStatus("connected");
  }

  function setEnded() {
    setStatus("ended");
  }

  return {
    status,
    setRinging,
    setConnected,
    setEnded
  };
}
