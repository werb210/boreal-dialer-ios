import { Client } from "@twilio/conversations";
import { getTwilioToken } from "./twilioTokenService";

let client: Client | null = null;

export async function initializeMessaging() {
  const { token } = await getTwilioToken();
  client = await Client.create(token);
}

export function getMessagingClient() {
  return client;
}
