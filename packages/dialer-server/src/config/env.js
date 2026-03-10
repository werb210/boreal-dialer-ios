import { z } from 'zod';

const envSchema = z.object({
  TWILIO_ACCOUNT_SID: z.string().min(1),
  TWILIO_API_KEY: z.string().min(1),
  TWILIO_API_SECRET: z.string().min(1),
  TWILIO_AUTH_TOKEN: z.string().min(1),
  REDIS_URL: z.string().min(1),
  BF_JWT_SECRET: z.string().min(1),
  ALLOWED_ORIGINS: z.string().min(1),
  TWILIO_TWIML_APP_SID: z.string().optional(),
  TWILIO_VOICE_APP_SID: z.string().optional(),
  VOICE_ENABLED: z.string().optional(),
  BASE_URL: z.string().optional(),
  NODE_ENV: z.string().optional(),
});

function validateEnv(rawEnv = process.env) {
  const parsed = envSchema.safeParse(rawEnv);
  if (!parsed.success) {
    const missing = parsed.error.issues.map((i) => i.path.join('.')).join(', ');
    throw new Error(`Invalid environment configuration: ${missing}`);
  }
  return parsed.data;
}

export { validateEnv };
