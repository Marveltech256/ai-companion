import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database, rpc } from './database.ts';
import { processMemoryJob } from '../../supabase/functions/_shared/memory.ts';
import { boundedCompanionContext, retrieveCompanionContext } from '../../supabase/functions/_shared/companion_context.ts';
import type { CompanionContext } from '../../supabase/functions/_shared/companion_context.ts';
import { companionInstructions } from '../../supabase/functions/_shared/openai.ts';

async function person(db:any,owner='alice',memory=true){
 await rpc(db,'morrow_bootstrap',{p_owner:owner});
 const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:owner,p_name:'Lumi',p_style:'Gentle & warm',p_interests:['Music'],p_response_length:.5,p_memory_enabled:memory,p_retention_days:null});
 return companion;
}
async function profile(db:any,owner:string,name:string|null,zone:string|null){
 return rpc(db,'morrow_save_personal_profile',{p_owner:owner,p_preferred_name:name,p_display_name:null,p_timezone:zone,p_language:'en',p_location:null});
}
async function say(db:any,owner:string,companion:string,content:string,candidates:any[],sourceTime?:string){
 const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:owner,p_companion:companion});
 const request=randomUUID();
 const turn=await rpc<any>(db,'morrow_begin_turn',{p_owner:owner,p_conversation:conversation.id,p_request:request,p_content:content});
 if(sourceTime)await db.query("update public.messages set created_at=$1 where request_id=$2 and role='user'",[sourceTime,request]);
 await rpc(db,'morrow_complete_turn',{p_owner:owner,p_request:request,p_lease:turn.lease,p_content:'A grounded test reply.'});
 await processMemoryJob({rpc:(name,args)=>rpc(db,name,args)},{extract:async()=>({memories:candidates})},owner,request);
 return conversation.id;
}
const fact=(key:string,category:string,quote:string,attributes:any)=>({key,category,quote,confidence:1,importance:.8,attributes});

test('preferred name survives a fresh conversation, corrections win, and another owner cannot retrieve it',async()=>{
 const db=await database();
 try{
  const alice=await person(db),bob=await person(db,'bob');
  await say(db,'alice',alice.id,'Marvin',[fact('identity.nickname','identity','Marvin',{field:'preferred_name',value:'Marvin',stability:'durable'})]);
  let context=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:alice.id});
  assert.equal(context.identity.preferred_name,'Marvin');
  await db.query("update public.profiles set display_name='Marvin Smith' where user_id='alice'");
  assert.equal((await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:alice.id})).identity.preferred_name,'Marvin');
  await profile(db,'alice','Carlos','Africa/Kampala');
  context=await rpc(db,'morrow_companion_context',{p_owner:'alice',p_companion:alice.id});
  assert.equal(context.identity.preferred_name,'Carlos');
  assert.ok(!context.memories.some(m=>m.attributes.field==='preferred_name'&&m.attributes.value==='Marvin'));
  const other=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'bob',p_companion:bob.id});
  assert.equal(other.identity.preferred_name,null);assert.equal(other.memories.length,0);
  await assert.rejects(rpc(db,'morrow_companion_context',{p_owner:'bob',p_companion:alice.id}),/not_found/);
  await profile(db,'alice',null,null);
  await say(db,'alice',alice.id,'Li',[fact('identity.name','identity','Li',{field:'preferred_name',value:'Li',stability:'durable'})]);
  assert.equal((await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:alice.id})).identity.preferred_name,'Li');
 }finally{await db.close();}
});

test('relative events use their original source time and timezone, not extraction time or invented local defaults',async()=>{
 const db=await database();
 try{
  const c=await person(db);await profile(db,'alice',null,'Africa/Kampala');
  await say(db,'alice',c.id,'I have a job interview tomorrow.',[fact('events.interview','events','I have a job interview tomorrow.',{relative_days:1,stability:'event',event_status:'planned'})],'2026-11-02T23:30:00Z');
  const context=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:c.id,p_now:'2026-11-05T08:00:00Z'});
  assert.equal(context.clock.local_date,'2026-11-05');
  const interview=context.memories.find(m=>m.kind==='event')!;
  assert.equal(interview.attributes.on_date,'2026-11-04');assert.equal(interview.event_state,'past_planned');
  const other=await person(db,'bob');
  await say(db,'bob',other.id,'I have a meeting tomorrow.',[fact('events.meeting','events','I have a meeting tomorrow.',{relative_days:1,stability:'event'})]);
  const unknown=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'bob',p_companion:other.id});
  assert.equal(unknown.clock.timezone,null);assert.equal(unknown.memories[0].temporal_status,'unresolved');
  assert.equal(unknown.memories[0].attributes.on_date,undefined);
 }finally{await db.close();}
});

test('explicit work/sleep routines and one-day exceptions survive across conversations',async()=>{
 const db=await database();
 try{
  const c=await person(db);await profile(db,'alice','Marvin','Europe/London');
  await say(db,'alice',c.id,'I work from Monday to Friday, 9 AM to 5 PM.',[fact('routines.work.weekly','routines','I work from Monday to Friday, 9 AM to 5 PM.',{routine_kind:'work',weekdays:[1,2,3,4,5],start_minute:540,end_minute:1020,block_notifications:true,stability:'durable'})]);
  let context=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:c.id,p_now:'2026-11-04T10:00:00Z'});
  assert.equal(context.current_routine!.find(r=>r.attributes.routine_kind==='work')!.active_now,true);
  await rpc(db,'morrow_save_structured_memory',{p_owner:'alice',p_companion:c.id,p_id:null,p_category:'routines',p_title:'Day off',p_content:'I am off work on 2026-11-04.',p_expires_at:null,p_attributes:{routine_kind:'work',on_date:'2026-11-04',skip:true}});
  context=await rpc(db,'morrow_companion_context',{p_owner:'alice',p_companion:c.id,p_now:'2026-11-04T10:00:00Z'});
  assert.ok(context.current_routine!.every(r=>r.active_now===false));
  assert.ok(context.previous_discussions.length>0);
 }finally{await db.close();}
});

test('first greeting is persisted once without a fake user message, extraction job or interaction count',async()=>{
 const db=await database();
 try{
  const c=await person(db);await rpc(db,'morrow_set_learning',{p_owner:'alice',p_companion:c.id,p_enabled:true});
  const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:'alice',p_companion:c.id});
  const request=randomUUID(),claim=await rpc<any>(db,'morrow_begin_greeting',{p_owner:'alice',p_conversation:conversation.id,p_request:request});
  await rpc(db,'morrow_complete_turn',{p_owner:'alice',p_request:request,p_lease:claim.lease,p_content:'Hi, I’m Lumi. What should I call you? You can skip that.'});
  const cached=await rpc<any>(db,'morrow_begin_greeting',{p_owner:'alice',p_conversation:conversation.id,p_request:randomUUID()});
  assert.equal(cached.status,'completed');assert.equal(cached.request_id,request);
  const {messages}=await rpc<any>(db,'morrow_messages',{p_owner:'alice',p_conversation:conversation.id});
  assert.equal(messages.length,1);assert.equal(messages[0].role,'assistant');
  assert.equal((await db.query('select count(*)::int as n from public.memory_jobs')).rows[0].n,0);
  assert.equal((await rpc<any>(db,'morrow_personalization',{p_owner:'alice',p_companion:c.id})).observations,null);
  const context=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:c.id});
  assert.equal(context.first_meeting.introduced,true);assert.equal(context.first_meeting.name_question_asked,true);
 }finally{await db.close();}
});

test('memory opt-out excludes cross-conversation facts while explicit profile settings remain available',async()=>{
 const db=await database();
 try{
  const c=await person(db);await say(db,'alice',c.id,'I enjoy jazz.',[fact('preferences.music','preferences','I enjoy jazz.',{stability:'durable'})]);
  await profile(db,'alice','Marvin','Africa/Kampala');
  await rpc(db,'morrow_save_companion',{p_owner:'alice',p_name:c.name,p_style:c.communication_style,p_interests:[],p_response_length:.5,p_memory_enabled:false,p_retention_days:null});
  const context=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:c.id});
  assert.equal(context.identity.preferred_name,'Marvin');assert.equal(context.memories.length,0);assert.equal(context.previous_discussions.length,0);
 }finally{await db.close();}
});

test('bounded context preserves category anchors and semantic rank cannot inject facts or foreign IDs',async()=>{
 const context:CompanionContext={identity:{preferred_name:'Marvin'},clock:{utc:'2026-11-03T00:00:00Z',timezone:null,local:null,local_date:null},
  first_meeting:{introduced:true,name_question_asked:true},previous_discussions:[],memories:[
   ...Array.from({length:20},(_,i)=>({id:`preference-${i}`,category:'preferences',kind:'preference',content:'x'.repeat(1200),attributes:{},verification:'user_stated',temporal_status:'durable',updated_at:'2026-11-03'})),
   {id:'event',category:'events',kind:'event',content:'Interview tomorrow.',attributes:{},verification:'user_stated',temporal_status:'planned',updated_at:'2026-11-03'}]};
 const result=await retrieveCompanionContext({rpc:async<T>()=>structuredClone(context) as T},'alice','companion','interview',null,{rank:async()=>['foreign-id','event']});
 assert.ok(result.memories.every(m=>m.id!=='foreign-id'));
 const bounded=boundedCompanionContext(result,true) as any;
 assert.ok(bounded.memories.some((m:any)=>m.id==='event'));assert.equal(bounded.identity.preferred_name,'Marvin');
 const prompt=companionInstructions({id:'c',name:'Lumi',communication_style:'Playful',response_length:.5,memory_enabled:true},[],null,result,'greeting');
 assert.match(prompt,/one optional question/);assert.match(prompt,/overrides older names/);assert.match(prompt,/not call UTC their local time/);
});

test('annual birthdays remain durable and leap-day occurrences use a real calendar date',async()=>{
 const db=await database();try{
  const c=await person(db);await profile(db,'alice','Marvin','Africa/Kampala');
  await say(db,'alice',c.id,'My birthday is February 29.',[fact('events.my_birthday','events','My birthday is February 29.',{annual:true,month:2,day:29,stability:'durable'})]);
  const ctx=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:c.id,p_now:'2028-02-01T08:00:00Z'});
  assert.equal(ctx.memories[0].event_date,'2028-02-29');assert.equal(ctx.memories[0].temporal_status,'durable');
  assert.equal((await rpc<any>(db,'morrow_list_memories',{p_owner:'alice',p_companion:c.id})).memories[0].expires_at,null);
  const next=await rpc<Date>(db,'morrow_event_date',{p_attributes:{annual:true,month:2,day:29},p_now:'2028-03-01T08:00:00Z',p_timezone:'Africa/Kampala'});
  assert.equal(next.toISOString().slice(0,10),'2032-02-29');
 }finally{await db.close();}
});

test('an overnight exception applies to its starting date and remains active after midnight',async()=>{
 const db=await database();try{
  const c=await person(db);await profile(db,'alice',null,'Etc/UTC');
  await rpc(db,'morrow_save_structured_memory',{p_owner:'alice',p_companion:c.id,p_id:null,p_category:'routines',p_title:'Sleep',p_content:'I sleep from 23:00 to 07:00.',p_expires_at:null,p_attributes:{routine_kind:'sleep',weekdays:[0,1,2,3,4,5,6],start_minute:1380,end_minute:420}});
  await rpc(db,'morrow_save_structured_memory',{p_owner:'alice',p_companion:c.id,p_id:null,p_category:'routines',p_title:'One late night',p_content:'On 2026-11-03 I sleep from 23:30 to 08:00.',p_expires_at:null,p_attributes:{routine_kind:'sleep',on_date:'2026-11-03',start_minute:1410,end_minute:480}});
  const ctx=await rpc<CompanionContext>(db,'morrow_companion_context',{p_owner:'alice',p_companion:c.id,p_now:'2026-11-04T07:30:00Z'});
  assert.equal(ctx.current_routine!.filter(r=>r.active_now).length,1);
  assert.equal(ctx.current_routine!.find(r=>r.active_now)!.attributes.end_minute,480);
 }finally{await db.close();}
});
