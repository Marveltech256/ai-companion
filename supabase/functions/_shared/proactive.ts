import type { Database } from './database.ts';
import type { AiProvider, CompanionConfig, HistoryMessage } from './openai.ts';
import type { Job, PushRoute } from './checkins.ts';
import { retrieveCompanionContext } from './companion_context.ts';

export function proactiveWriter(db:Database,ai:AiProvider){
 return async(job:Job):Promise<PushRoute>=>{
  await db.rpc('morrow_require_eligible',{p_owner:job.owner_id});
  const claim=await db.rpc<{status:string;lease:string;request_id:string;conversation_id:string;companion:CompanionConfig;reason:string;history:HistoryMessage[]}>(
   'morrow_begin_proactive',{p_owner:job.owner_id,p_id:job.id,p_lease:job.lease});
  if(claim.status==='completed')return {checkin_id:job.id,conversation_id:claim.conversation_id};
  try{
   const context=await retrieveCompanionContext(db,job.owner_id,claim.companion.id,claim.reason,claim.conversation_id);
   let text='';
   for await(const delta of ai.reply({companion:claim.companion,history:claim.history??[],memories:[],context,purpose:'proactive',reason:{confirmed_reason:claim.reason}},AbortSignal.timeout(60000))){
    text+=delta;if(text.length>12000)throw new Error('reply_too_long');
   }
   if(!text.trim())throw new Error('empty_reply');
   // Recheck after generation, before persisting or contacting the push provider.
   const permission=await db.rpc<{allowed:boolean}>('morrow_authorize_checkin',{p_id:job.id,p_lease:job.lease});
   if(!permission.allowed)throw new Error('checkin_suppressed');
   await db.rpc('morrow_complete_turn',{p_owner:job.owner_id,p_request:claim.request_id,p_lease:claim.lease,p_content:text});
   return {checkin_id:job.id,conversation_id:claim.conversation_id};
  }catch(error){
   await db.rpc('morrow_fail_turn',{p_owner:job.owner_id,p_request:claim.request_id,p_lease:claim.lease}).catch(()=>{});
   throw error;
  }
 };
}
