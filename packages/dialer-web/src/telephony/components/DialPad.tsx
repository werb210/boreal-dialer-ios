import { useEffect, useState } from "react";
import { startDialerSession } from "../services/voiceDevice";
import { setUiError } from "../state/callStore";
import { getDialPrefill, subscribeDialPrefill } from "../../state/dialPrefill";
export default function DialPad(){const[number,setNumber]=useState(getDialPrefill());useEffect(()=>subscribeDialPrefill((value)=>setNumber(value)),[]);const handleDial=async()=>{if(!number)return;try{await startDialerSession(number);setUiError(null);}catch(error){const message=error instanceof Error?error.message:"Unknown error";setUiError(`Call start failed: ${message}`);}};return <div style={{padding:20}}><h2>Dial</h2><input value={number} onChange={(event)=>setNumber(event.target.value)} placeholder="Phone number" style={{width:"100%",padding:10,marginBottom:10,boxSizing:"border-box"}}/><button onClick={handleDial} style={{padding:"10px 16px"}}>Call</button></div>}
