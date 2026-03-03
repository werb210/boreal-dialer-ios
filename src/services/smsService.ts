import { Client } from "@twilio/conversations";

let client: Client | null = null;

export async function initializeMessaging(identity: string) {

  const res = await fetch("/api/telephony/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ identity })
  });

  const data = await res.json();

  client = await Client.create(data.token);
}

export function getMessagingClient() {
  return client;
}
