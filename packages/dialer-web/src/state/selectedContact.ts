export type SelectedContact={id:string;name:string;phone:string}|null; let current:SelectedContact=null; const subscribers=new Set<(value:SelectedContact)=>void>();
export const getSelectedContact=():SelectedContact=>current; export function setSelectedContact(value:SelectedContact):void{ current=value; subscribers.forEach((notify)=>notify(value)); }
export function subscribeSelectedContact(listener:(value:SelectedContact)=>void):()=>void{subscribers.add(listener); return()=>subscribers.delete(listener);}
