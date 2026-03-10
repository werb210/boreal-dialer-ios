import { initDevice } from "./device";

export async function refreshVoice(token: string) {
  return initDevice(token);
}
