import { Device, Call } from "@twilio/voice-sdk";
import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

let device: Device | null = null;

type TelephonyTokenPayload = {
  token: string;
};

export async function initializeVoice(identity: string) {
  const response = await api.post(TELEPHONY_TOKEN_ENDPOINT, { identity });
  const data = assertApiResponse<TelephonyTokenPayload>(response.data);

  if (!data.token) {
    throw new Error("Request failed");
  }

  device = new Device(data.token, {
    codecPreferences: [Call.Codec.Opus, Call.Codec.PCMU]
  });

  device.on("incoming", (call: Call) => {
    call.accept();
  });

  device.register();
}

export function getDevice() {
  return device;
}

export async function makeCall(to: string) {
  if (!device) {
    throw new Error("Device not initialized");
  }

  return device.connect({
    params: { to }
  });
}
