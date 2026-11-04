import { createCompanionApi } from "../_shared/companion_api.ts";
import { runtime } from "../_shared/runtime.ts";
import { createTextAi } from '../_shared/text_ai.ts';
import { processMemoryJob } from '../_shared/memory.ts';

const deps=runtime(name=>Deno.env.get(name));
const ai=createTextAi(name=>Deno.env.get(name));
declare const EdgeRuntime:{waitUntil(work:Promise<unknown>):void};
Deno.serve(createCompanionApi({...deps,
  recover:async(owner)=>{
    // Restoring an account can precede its adult introduction. Do not process
    // queued transcript memories until the same eligibility gate permits AI.
    try{await deps.friendEligible(owner);}catch{return;}
    const pending=await deps.db.rpc<{requests:string[]}>('morrow_pending_memory_jobs',{p_owner:owner});
    for(const request of pending.requests)await processMemoryJob(deps.db,ai,owner,request);
  },defer:(work)=>EdgeRuntime.waitUntil(work),
}));
