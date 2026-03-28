import { Client } from "@twilio/conversations";
import { assertApiResponse } from "../lib/assertApiResponse";
import { api } from "../network/api";

let client: Client | null = null;

type TelephonyTokenPayload = {
  token: string;
};

export async function initializeMessaging(identity: string) {
  const response = await api.post("/api/telephony/token", { identity });
  const data = assertApiResponse<TelephonyTokenPayload>(response.data);

  client = await Client.create(data.token);
}

export function getMessagingClient() {
  return client;
}
