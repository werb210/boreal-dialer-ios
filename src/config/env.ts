export function requireEnv(name: string): string {
  const value = import.meta.env[name];
  if (!value) {
    throw new Error(`Missing required env variable: ${name}`);
  }
  return value;
}

export const twilioEnv = {
  accountSid: requireEnv("TWILIO_ACCOUNT_SID"),
  apiKey: requireEnv("TWILIO_API_KEY"),
  apiSecret: requireEnv("TWILIO_API_SECRET")
};
