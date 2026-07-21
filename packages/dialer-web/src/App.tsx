import { useEffect, useState } from "react";
import { initializeDialerAuthState } from "./auth/useDialerAuth";
import { startDialerSession } from "./telephony/services/voiceDevice";
import { setUiError } from "./telephony/state/callStore";
import IncomingCallOverlay from "./telephony/components/IncomingCallOverlay";
import LoginGate from "./ui/LoginGate";
import RootTabs from "./ui/RootTabs";
export default function App(){const[authed,setAuthed]=useState(false);const[ready,setReady]=useState(false);useEffect(()=>{initializeDialerAuthState().then((state)=>setAuthed(Boolean(state.token))).catch(()=>setAuthed(false)).finally(()=>setReady(true));},[]);useEffect(()=>{if(!authed)return;startDialerSession().catch((error:unknown)=>{const message=error instanceof Error?error.message:"Unknown error";setUiError(`Telephony initialization failed: ${message}`);});},[authed]);if(!ready)return <div style={{padding:24,fontFamily:"system-ui"}}>Loading...</div>;return <><IncomingCallOverlay />{authed?<RootTabs onLogout={()=>setAuthed(false)} />:<LoginGate onAuthed={()=>setAuthed(true)} />}</>}
