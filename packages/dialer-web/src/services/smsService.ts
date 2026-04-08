import { Client } from "@twilio/conversations";
import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";
import { TELEPHONY_TOKEN_ENDPOINT } from "../constants/endpoints";

let client: Client | null = null;

type TelephonyTokenPayload = {
  token: string;
};

export async function initializeMessaging(identity: string) {
  const response = await api.post(TELEPHONY_TOKEN_ENDPOINT, { identity });
  const data = assertApiResponse<TelephonyTokenPayload>(response.data);

  client = await Client.create(data.token);
}

export function getMessagingClient() {
  return client;
}
