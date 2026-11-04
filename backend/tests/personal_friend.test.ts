import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {database,rpc} from './database.ts';
import {companionInstructions} from '../../supabase/functions/_shared/openai.ts';
import {createConversationTurn} from '../../supabase/functions/_shared/conversation_turn.ts';
import {ApiError} from '../../supabase/functions/_shared/errors.ts';

async function person(db:any,owner='alice'){
 await rpc(db,'morrow_bootstrap',{p_owner:owner});
 await rpc(db,'morrow_save_named_profile',{p_owner:owner,p_username:owner,p_preferred_name:owner,
  p_display_name:null,p_timezone:null,p_language:null,p_location:null});
 const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:owner,p_name:'Lumi',p_style:'Gentle & warm',
  p_interests:[],p_response_length:.3,p_memory_enabled:true,p_retention_days:null});
 return companion;
}

test('18+ introduction is explicit, service-only, language-aware and survives welcome completion',async()=>{
 const db=await database();try{
  const c=await person(db);await person(db,'bobby');
  await assert.rejects(rpc(db,'morrow_require_eligible',{p_owner:'alice'}),/introduction_required/);
  for(const age of [null,'15_17','under_15','14','under_18'])await assert.rejects(rpc(db,'morrow_save_introduction',{
   p_owner:'alice',p_age_group:age,p_language:'fr',p_timezone:'Africa/Kampala'}),/invalid_input/);
  const {profile}=await rpc<any>(db,'morrow_save_introduction',{p_owner:'alice',p_age_group:'18_24',p_language:'fr',p_timezone:'Africa/Kampala'});
  assert.ok(profile.introduction_completed_at);assert.equal(profile.welcome_completed_at,null);
  assert.deepEqual(await rpc(db,'morrow_require_eligible',{p_owner:'alice'}),{ok:true});
  const ctx=await rpc<any>(db,'morrow_personal_context',{p_owner:'alice',p_companion:c.id});
  assert.equal(ctx.identity.age_group,'18_24');assert.equal(ctx.identity.language,'fr');
  const instructions=companionInstructions(c,[],null,ctx);
  assert.ok(instructions.includes('18_24'));
  assert.ok(instructions.includes('default for every reply'));
  await assert.rejects(rpc(db,'morrow_personal_context',{p_owner:'bobby',p_companion:c.id}),/not_found/);
  const first=await rpc<any>(db,'morrow_complete_welcome',{p_owner:'alice'});
  const second=await rpc<any>(db,'morrow_complete_welcome',{p_owner:'alice'});
  assert.equal(first.profile.welcome_completed_at,second.profile.welcome_completed_at);
  const privilege=await db.query<any>("select has_function_privilege('authenticated','public.morrow_save_introduction(text,text,text,text)','EXECUTE') allowed");
  assert.equal(privilege.rows[0].allowed,false);
 }finally{await db.close();}
});

test('inactivity check-ins wait for the configured gap and stop until a user replies; reminders stay separate',async()=>{
 const db=await database();try{
  const c=await person(db);
  const base=new Date();base.setUTCDate(base.getUTCDate()+5);base.setUTCHours(10,0,0,0);
  const time=(day:number,minute=1)=>new Date(base.getTime()+day*86400000+minute*60000).toISOString();
  await db.query("update public.profiles set created_at=$1 where user_id='alice'",[time(-3,0)]);
  const schedule={p_owner:'alice',p_companion:c.id,p_checkins:true,p_suggestions:false,p_birthdays:true,
   p_timezone:'Africa/Kampala',p_local_minute:780,p_weekdays:[0,1,2,3,4,5,6],p_quiet_start:1320,p_quiet_end:480,
   p_additional:[],p_max:1,p_inactivity_days:2};
  await rpc(db,'morrow_save_friend_schedule',schedule);
  await rpc(db,'morrow_register_device',{p_owner:'alice',p_installation:randomUUID(),p_token:'test-device-registration-token-12345'});
  await db.query("update public.device_tokens set updated_at=$1 where owner_id='alice'",[time(0,0)]);
  assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:time(-2)})).jobs.length,0);
  const {jobs}=await rpc<any>(db,'morrow_due_checkins',{p_now:time(0)});assert.equal(jobs.length,1);
  await db.query("update public.scheduled_checkins set created_at=$1 where id=$2",[time(0),jobs[0].id]);
  assert.equal((await rpc<any>(db,'morrow_checkin_permission',{p_id:jobs[0].id,p_lease:jobs[0].lease,p_now:time(0)})).allowed,true);
  await rpc(db,'morrow_finish_checkin',{p_id:jobs[0].id,p_lease:jobs[0].lease,p_status:'sent'});
  assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:time(1)})).jobs.length,0);
  const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:'alice',p_companion:c.id});
  const id=randomUUID(),claim=await rpc<any>(db,'morrow_begin_turn',{p_owner:'alice',p_conversation:conversation.id,p_request:id,p_content:'I am back.'});
  await rpc(db,'morrow_complete_turn',{p_owner:'alice',p_request:id,p_lease:claim.lease,p_content:'Welcome back.'});
  await db.query("update public.messages set created_at=$1 where request_id=$2 and role='user'",[time(1,60),id]);
  assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:time(2)})).jobs.length,0);
  assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:time(4)})).jobs.length,1);
  const reminderLocal=time(5).slice(0,10)+'T13:15:00';
  await rpc(db,'morrow_schedule_personal_reminder',{p_owner:'alice',p_kind:'important_date',p_local:reminderLocal,
   p_zone:'Africa/Kampala',p_reason:'Submit my application',p_conversation:null,p_source:null,p_request:randomUUID()});
  const summary=await rpc<any>(db,'morrow_home_summary',{p_owner:'alice',p_companion:c.id,p_now:time(4,2)});
  assert.equal(summary.reminders.length,1);assert.equal(summary.reminders[0].reason,'Submit my application');
  assert.equal(summary.reminders[0].local_time,reminderLocal);assert.equal(summary.events.length,0);
  const other=await person(db,'bobby');
  assert.equal((await rpc<any>(db,'morrow_home_summary',{p_owner:'bobby',p_companion:other.id})).reminders.length,0);
 }finally{await db.close();}
});

test('a registered but unconfirmed account cannot invoke conversation generation directly',async()=>{
 let providerCalls=0,claims=0;
 const handler=createConversationTurn({origins:[],verify:async()=>({uid:'alice'}) as any,
  eligible:async()=>{throw new ApiError(403,'introduction_required','Confirm your age range.');},
  db:{rpc:async<T>()=>{claims++;return {} as T;}},ai:{async *reply(){providerCalls++;yield 'Unexpected';}}});
 const response=await handler(new Request('https://test.local',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({conversation_id:randomUUID(),request_id:randomUUID(),content:'Hello'})}));
 assert.equal(response.status,403);assert.equal((await response.json()).code,'introduction_required');
 assert.equal(providerCalls,0);assert.equal(claims,0);
});
