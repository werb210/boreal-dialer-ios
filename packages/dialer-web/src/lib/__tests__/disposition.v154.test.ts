import { describe, it, expect } from "vitest";
import { toDispositions, confirmationFor } from "../disposition";
const SERVER=["connected","left_voicemail","no_answer","follow_up","not_interested","do_not_contact","demo_booked","documents_promised","needs_lender_review"];
describe("BOREAL_DIALER_DISPOSITION_v154",()=>{
 it("offers and orders server outcomes",()=>{const ids=toDispositions(SERVER).map(d=>d.id); expect([...ids].sort()).toEqual([...SERVER].sort()); expect(ids[0]).toBe("connected"); expect(ids.at(-1)).toBe("do_not_contact");});
 it("marks task outcomes and preserves unknown values",()=>{const out=toDispositions([...SERVER,"callback_scheduled"]); expect(out.find(d=>d.id==="follow_up")?.createsTask).toBe(true); expect(out.find(d=>d.id==="do_not_contact")?.createsTask).toBe(false); expect(out.at(-1)?.label).toBe("callback scheduled");});
 it("confirms saves",()=>expect(confirmationFor("documents_promised",true)).toBe("Documents promised — follow-up task created"));
});
