import { destroyDevice, getDevice } from "./device";

export async function refreshVoice(token: string) {
  destroyDevice();
  return getDevice(token);
}
