let current=""; const subscribers=new Set<(value:string)=>void>();
export const getDialPrefill=():string=>current; export function setDialPrefill(value:string):void{ current=value; subscribers.forEach((notify)=>notify(value)); }
export function subscribeDialPrefill(listener:(value:string)=>void):()=>void{subscribers.add(listener); return()=>subscribers.delete(listener);}
