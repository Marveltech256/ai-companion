import { createConversationTurn } from '../_shared/conversation_turn.ts';
import { createTextAi,createMemoryReranker } from '../_shared/text_ai.ts';
import { runtime } from '../_shared/runtime.ts';
import { processMemoryJob } from '../_shared/memory.ts';
import type { MemoryFact } from '../_shared/openai.ts';
import { retrieveCompanionContext } from '../_shared/companion_context.ts';
import {billingAccessDatabase} from '../_shared/billing_access.ts';

const base=runtime(name=>Deno.env.get(name));
const dependencies={...base,db:billingAccessDatabase(base,name=>Deno.env.get(name))};
const ai=createTextAi(name=>Deno.env.get(name));
declare const EdgeRuntime: {waitUntil(work:Promise<unknown>):void};
const reranker=createMemoryReranker(name=>Deno.env.get(name));
Deno.serve(createConversationTurn({...dependencies,ai,
  context:(owner,companion,query,conversation)=>retrieveCompanionContext(dependencies.db,owner,companion,query,conversation,reranker),
  personalization:async(owner,companion)=>{
    const result=await dependencies.db.rpc<{observations:import('../_shared/openai.ts').Observations|null}>(
      'morrow_personalization',{p_owner:owner,p_companion:companion});
    return result.observations;
  },
  memories:async(owner,companion,query)=>{
    const result=await dependencies.db.rpc<{memories:MemoryFact[]}>('morrow_search_memories',{
      p_owner:owner,p_companion:companion,p_query:query,p_limit:8});
    return result.memories;
  },
  completed:(owner,request)=>processMemoryJob(dependencies.db,ai,owner,request),
  defer:(work)=>EdgeRuntime.waitUntil(work),
}));
