import { useEffect, useRef, useState } from "react";
// BOREAL_DIALER_SNIPPETS_v156
import ComposerTools from "./ComposerTools";
import { fetchSnippets, expandShortcut, insertAt, type Snippet } from "../lib/snippets"; import { fetchSmsThread, sendSms, type SmsMessage } from "../lib/apiClient"; import { getSelectedContact, subscribeSelectedContact, type SelectedContact } from "../state/selectedContact";
export default function SmsTab(){const[contact,setContact]=useState<SelectedContact>(getSelectedContact());const[to,setTo]=useState(getSelectedContact()?.phone??"");const[body,setBody]=useState("");const[thread,setThread]=useState<SmsMessage[]>([]);const[status,setStatus]=useState<string|null>(null);
  // BOREAL_DIALER_SNIPPETS_v156 — "#shortcut" plus space expands in place, the
  // same trigger the portal composer uses.
  const[snips,setSnips]=useState<Snippet[]>([]);
  const boxRef=useRef<HTMLTextAreaElement|null>(null);
  useEffect(()=>{void fetchSnippets("sms").then(setSnips)},[]);
  function onKeyDown(e:React.KeyboardEvent<HTMLTextAreaElement>){
    if(e.key!==" "&&e.key!=="Tab"&&e.key!=="Enter")return;
    const el=e.currentTarget;const caret=el.selectionStart??el.value.length;
    const out=expandShortcut(el.value,caret,snips);
    if(!out)return;
    e.preventDefault();setBody(out.value);
    setTimeout(()=>{try{el.setSelectionRange(out.caret,out.caret)}catch{/* unmounted */}},0);
  }
  function insert(text:string){
    const el=boxRef.current;const caret=el?.selectionStart??body.length;
    const out=insertAt(body,caret,text);setBody(out.value);
    setTimeout(()=>{try{el?.focus();el?.setSelectionRange(out.caret,out.caret)}catch{/* unmounted */}},0);
  }useEffect(()=>subscribeSelectedContact(n=>{setContact(n);setTo(n?.phone??"")}),[]); async function load(){if(!contact?.id&&!to.trim())return; setThread(await fetchSmsThread({contactId:contact?.id,phone:contact?.id?undefined:to.trim()}));} useEffect(()=>{void load()},[contact?.id]); async function send(){await sendSms({to:to.trim(),body:body.trim(),contactId:contact?.id});setBody("");setStatus("Sent");await load();} return <div style={{padding:16}}><h3>SMS{contact?.name?` - ${contact.name}`:""}</h3><input value={to} onChange={e=>setTo(e.target.value)} placeholder="To (e.g. +15875551234)"/>{thread.map((m,i)=><p key={m.id??i}>{m.direction} {m.created_at??m.timestamp}: {m.body??m.text}</p>)}<ComposerTools channel="sms" onInsert={insert}/><textarea ref={boxRef} value={body} onChange={e=>setBody(e.target.value)} onKeyDown={onKeyDown} placeholder="Message, or type #shortcut"/><button onClick={()=>void send()} disabled={!to.trim()||!body.trim()}>Send</button><button onClick={()=>void load()}>Refresh</button>{status&&<p>{status}</p>}</div>}
