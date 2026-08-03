// BOREAL_DIALER_WEB_JOIN_CONFERENCE_v47 - VOICE_CALLS added below; the
// request interceptor in network/api.ts throws INVALID_API_PATH for
// anything absent from this list.
const configuredApiBase = import.meta.env.VITE_API_URL;
if (!configuredApiBase || configuredApiBase.trim() === "") throw new Error("MISSING_VITE_API_URL");
export const API_BASE = configuredApiBase;
export const API_ENDPOINTS = Object.freeze({VOICE_RECENT:"/api/voice/recent-calls",VOICE_CALLS:"/api/voice/calls",TELEPHONY_TOKEN:"/api/telephony/token",OTP_START:"/api/auth/otp/start",OTP_VERIFY:"/api/auth/otp/verify",CRM_CONTACTS:"/api/crm/contacts",TEAM_USERS:"/api/team/users",COMMS_SMS:"/api/communications/sms",COMMS_SMS_THREAD:"/api/communications/sms/thread",COMMS_MESSAGES_LIST:"/api/communications/messages-list",COMMS_MESSAGES_THREAD:"/api/communications/messages/thread",COMMS_MESSAGES_SEND:"/api/communications/messages/send",CALENDAR_EVENTS:"/api/calendar/events",CALENDAR_TASKS:"/api/calendar/tasks"} as const);
export const TelephonyEndpoint = Object.freeze({TOKEN: API_ENDPOINTS.TELEPHONY_TOKEN} as const);
if (import.meta.env.DEV) { console.assert(Object.isFrozen(API_ENDPOINTS)); console.assert(Object.isFrozen(TelephonyEndpoint)); }
export type TelephonyEndpoint = (typeof TelephonyEndpoint)[keyof typeof TelephonyEndpoint];
export const TELEPHONY_TOKEN_ENDPOINT: TelephonyEndpoint = TelephonyEndpoint.TOKEN;
