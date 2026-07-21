import { API_BASE, API_ENDPOINTS } from "../constants/endpoints";
import { getValidAuthToken } from "../auth/useDialerAuth";
export function buildUrl(path:string, query?:Record<string,string|number|undefined>): string { const url = new URL(path, API_BASE); Object.entries(query ?? {}).forEach(([k,v]) => { if (v !== undefined && v !== "") url.searchParams.set(k,String(v)); }); return url.toString(); }
function authHeaders(): Record<string,string> { const h: Record<string,string>={"Content-Type":"application/json","X-Silo":"BF"}; try { const t=getValidAuthToken(); if (t) h.Authorization=`Bearer ${t}`; } catch {} return h; }
export async function apiGet<T>(path:string, query?:Record<string,string|number|undefined>):Promise<T>{ const r=await fetch(buildUrl(path,query),{method:"GET",headers:authHeaders()}); if(!r.ok) throw new Error(`GET ${path} -> ${r.status}`); return await r.json() as T; }
export async function apiPost<T>(path:string, body:unknown):Promise<T>{ const r=await fetch(buildUrl(path),{method:"POST",headers:authHeaders(),body:JSON.stringify(body)}); if(!r.ok) throw new Error(`POST ${path} -> ${r.status}`); return await r.json() as T; }
export type Contact={id:string;full_name?:string;first_name?:string;last_name?:string;name?:string;phone?:string;mobile?:string;mobile_phone?:string;work_phone?:string;email?:string};
export const contactName=(c:Contact):string=>c.full_name||c.name||[c.first_name,c.last_name].filter(Boolean).join(" ")||"(no name)";
export const contactPhone=(c:Contact):string=>c.phone||c.mobile||c.mobile_phone||c.work_phone||"";
export async function fetchContacts(search:string):Promise<Contact[]>{ const r=await apiGet<{data?:Contact[]}>(API_ENDPOINTS.CRM_CONTACTS,{pageSize:100,search}); return Array.isArray(r.data)?r.data:[]; }
export type TeamUser={id?:string;name?:string;email?:string;role?:string;phone?:string};
export async function fetchTeam():Promise<TeamUser[]>{ const r=await apiGet<{users?:TeamUser[]}>(API_ENDPOINTS.TEAM_USERS); return Array.isArray(r.users)?r.users:[]; }
export type SmsMessage={id?:string;body?:string;text?:string;direction?:string;created_at?:string;timestamp?:string};
const rows=(r:{data?:SmsMessage[];messages?:SmsMessage[];rows?:SmsMessage[]})=>r.data??r.messages??r.rows??[];
export async function fetchSmsThread(p:{contactId?:string;phone?:string}):Promise<SmsMessage[]>{ return rows(await apiGet(API_ENDPOINTS.COMMS_SMS_THREAD,{contactId:p.contactId,phone:p.phone})); }
export async function sendSms(p:{to:string;body:string;contactId?:string}):Promise<void>{ await apiPost(API_ENDPOINTS.COMMS_SMS,p); }
export type RecentCall={id?:string;direction?:string;status?:string;duration_seconds?:number;created_at?:string;started_at?:string;phone_number?:string;phone?:string;contact_id?:string;contact_name?:string};
export const recentCallPhone=(c:RecentCall):string=>c.phone_number??c.phone??""; export const recentCallWhen=(c:RecentCall):string=>c.created_at??c.started_at??"";
export async function fetchRecentCalls():Promise<RecentCall[]>{ const r=await apiGet<{items?:RecentCall[];data?:RecentCall[]}>(API_ENDPOINTS.VOICE_RECENT); return r.items??r.data??[]; }
export type Conversation={contact_id?:string;thread_key?:string;display_name?:string;name?:string;phone?:string;email?:string;last_body?:string};
export const conversationId=(c:Conversation):string=>c.contact_id??c.thread_key??""; export const conversationName=(c:Conversation):string=>c.display_name||c.name||c.phone||"(no name)";
export async function fetchConversations():Promise<Conversation[]>{ const r=await apiGet<{conversations?:Conversation[]}>(API_ENDPOINTS.COMMS_MESSAGES_LIST,{mode:"all"}); return Array.isArray(r.conversations)?r.conversations:[]; }
export async function fetchMessageThread(contactId:string):Promise<SmsMessage[]>{ return rows(await apiGet(API_ENDPOINTS.COMMS_MESSAGES_THREAD,{contactId})); }
export async function sendMessage(p:{contactId:string;body:string}):Promise<void>{ await apiPost(API_ENDPOINTS.COMMS_MESSAGES_SEND,p); }
export type CalendarEvent={id?:string;title?:string;start?:string;end?:string;location?:string}; export type CalendarTask={id?:string;title?:string;due_at?:string|null;priority?:string;status?:string};
export async function fetchEvents():Promise<CalendarEvent[]>{ const r=await apiGet<{data?:CalendarEvent[]}>(API_ENDPOINTS.CALENDAR_EVENTS); return Array.isArray(r.data)?r.data:[]; }
export async function fetchTasks():Promise<CalendarTask[]>{ const r=await apiGet<{data?:CalendarTask[];tasks?:CalendarTask[]}>(API_ENDPOINTS.CALENDAR_TASKS,{status:"open"}); return r.data??r.tasks??[]; }
