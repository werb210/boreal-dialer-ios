import { destroyDevice, initDevice } from "../twilio/deviceManager";

export type DialerAuthState = {
  token: string | null;
};

let authState: DialerAuthState = { token: null };

export async function login(token: string): Promise<void> {
  authState = { token };
  await initDevice(token);
}

export function logout(): void {
  authState = { token: null };
  destroyDevice();
}

export function getDialerAuthState(): DialerAuthState {
  return authState;
}
