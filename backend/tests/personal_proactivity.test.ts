import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {database,rpc} from './database.ts';
import {proactiveWriter} from '../../supabase/functions/_shared/proactive.ts';
import {createCheckinDispatcher} from '../../supabase/functions/_shared/checkins.ts';

async function setup(db:any,zone='Europe/London',maximum=1,additional:number[]=[]){
 await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
 await db.exec("update public.profiles set age_group='25_34',introduction_completed_at=now() where user_id='alice'");
 const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Lumi',p_style:'Reflective',p_interests:[],p_response_length:.5,p_memory_enabled:true,p_retention_days:null});
 const args={p_owner:'alice',p_companion:companion.id,p_checkins:true,p_suggestions:true,p_birthdays:true,p_timezone:zone,p_local_minute:420,p_weekdays:[0,1,2,3,4,5,6],p_quiet_start:1260,p_quiet_end:360,p_additional:additional,p_max:maximum};
 await rpc(db,'morrow_save_personal_schedule',args);
 await rpc(db,'morrow_register_device',{p_owner:'alice',p_installation:randomUUID(),p_token:'owned-device-fid-1234567890'});
 return {companion,args};
}
async function memory(db:any,c:string,category:string,content:string,attributes:any){
 return rpc<any>(db,'morrow_save_structured_memory',{p_owner:'alice',p_companion:c,p_id:null,p_category:category,p_title:'User detail',p_content:content,p_expires_at:null,p_attributes:attributes});
}

test('multiple local slots obey frequency, deduplication, quiet hours and saved work boundaries',async()=>{
 const db=await database();try{
  const {companion}=await setup(db,'Europe/London',2,[1080]);
  await db.query("update public.device_tokens set updated_at='2027-11-03T06:00:00Z'");
  const morning=await rpc<any>(db,'morrow_due_checkins',{p_now:'2027-11-03T07:02:00Z'});assert.equal(morning.jobs.length,1);
  assert.match(morning.jobs[0].reason,/requested a recurring/);
  assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:'2027-11-03T07:03:00Z'})).jobs.length,0);
  const evening=await rpc<any>(db,'morrow_due_checkins',{p_now:'2027-11-03T18:02:00Z'});assert.equal(evening.jobs.length,1);
  assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:'2027-11-03T18:03:00Z'})).jobs.length,0);
  assert.equal((await rpc<any>(db,'morrow_checkin_permission',{p_id:evening.jobs[0].id,p_lease:evening.jobs[0].lease,p_now:'2027-11-03T21:00:00Z'})).allowed,false);
  await memory(db,companion.id,'routines','I work Wednesday from 7 to 9.',{routine_kind:'work',weekdays:[3],start_minute:420,end_minute:540,block_notifications:true});
  assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:'2027-11-10T07:01:00Z'})).jobs.length,0);
 }finally{await db.close();}
});

test('contextual jobs are revoked when their source is corrected, forgotten, or memory is disabled',async()=>{
 const db=await database();try{
  const {companion}=await setup(db);
  const saved=await memory(db,companion.id,'events','Interview on 2027-11-03.',{on_date:'2027-11-03',timezone:'Europe/London',event_status:'planned'});
  await db.query("update public.device_tokens set updated_at='2027-11-03T06:00:00Z'");
  const {jobs}=await rpc<any>(db,'morrow_due_checkins',{p_now:'2027-11-03T07:01:00Z'}),job=jobs[0];
  assert.match(job.reason,/Interview/);
  const permission=()=>rpc<any>(db,'morrow_checkin_permission',{p_id:job.id,p_lease:job.lease,p_now:'2027-11-03T07:01:30Z'});
  assert.equal((await permission()).allowed,true);
  await db.query("update public.memories set updated_at=updated_at+interval '1 second' where owner_id='alice'");
  assert.equal((await permission()).allowed,false);
  await db.query("delete from public.memories where owner_id='alice'");
  assert.equal((await permission()).allowed,false);
  assert.equal((await rpc<any>(db,'morrow_checkin_history',{p_owner:'bob'})).checkins.length,0);
 }finally{await db.close();}
});

test('explicit reminders reject DST ambiguity and clock gaps; timezone changes cancel pending delivery',async()=>{
 const db=await database();try{
  const {args}=await setup(db,'America/New_York');
  // Temporarily permit the DST transition hours to test wall-time validation.
  await rpc(db,'morrow_save_personal_schedule',{...args,p_local_minute:90,p_quiet_start:240,p_quiet_end:0});
  const base={p_owner:'alice',p_kind:'important_date',p_zone:'America/New_York',p_reason:'My appointment'};
  await assert.rejects(rpc(db,'morrow_schedule_personal_reminder',{...base,p_local:'2027-11-07T01:30:00'}),/ambiguous_local_time/);
  await assert.rejects(rpc(db,'morrow_schedule_personal_reminder',{...base,p_local:'2027-03-14T02:30:00'}),/ambiguous_local_time/);
  const due=new Date(Date.now()+2*86400000).toISOString().slice(0,10)+'T03:00:00';
  const request=randomUUID();
  const reminder=await rpc<any>(db,'morrow_schedule_personal_reminder',{...base,p_local:due,p_request:request});
  assert.equal((await rpc<any>(db,'morrow_schedule_personal_reminder',{...base,p_local:due,p_request:request})).checkin.id,reminder.checkin.id);
  await assert.rejects(rpc(db,'morrow_schedule_personal_reminder',{...base,p_reason:'Different reminder',p_local:due,p_request:request}),/request_conflict/);
  assert.equal(reminder.checkin.status,'queued');assert.equal(reminder.checkin.provider_accepted_at,null);
  await rpc(db,'morrow_save_personal_profile',{p_owner:'alice',p_preferred_name:'Marvin',p_display_name:null,p_timezone:'Africa/Kampala',p_language:null,p_location:null});
  const {checkins}=await rpc<any>(db,'morrow_checkin_history',{p_owner:'alice'});
  assert.equal(checkins[0].status,'suppressed');assert.match(checkins[0].outcome_detail,/Timezone changed/);
 }finally{await db.close();}
});

test('proactive writer persists one owned assistant message and routes receipts without claiming delivery',async()=>{
 const db=await database();try{
  const {companion}=await setup(db,'Etc/UTC');
  await rpc(db,'morrow_save_personal_profile',{p_owner:'alice',p_preferred_name:'Marvin',p_display_name:null,p_timezone:'Etc/UTC',p_language:null,p_location:null});
  // Current-time worker fixture permits dispatch at any hour; no physical push is sent.
  await db.query("update public.notification_preferences set quiet_start=0,quiet_end=0");
  const id=randomUUID(),lease=randomUUID();
  await db.query("insert into public.scheduled_checkins(id,owner_id,kind,due_at,status,lease,lease_until,preference_revision,reason) select $1,'alice','checkin',now(),'sending',$2,now()+interval '2 minutes',revision,'Requested morning hello' from public.notification_preferences where owner_id='alice'",[id,lease]);
  let input:any,calls=0;
  const writer=proactiveWriter({rpc:(n,a)=>rpc(db,n,a)},{reply:async function*(i){input=i;calls++;yield 'Good morning, Marvin. How are you?';}});
  const job={id,lease,owner_id:'alice',companion_id:companion.id,devices:[]};
  const route=await writer(job);assert.equal(input.context.identity.preferred_name,'Marvin');assert.equal(input.purpose,'proactive');
  assert.deepEqual(await writer(job),route);assert.equal(calls,1);
  assert.equal((await db.query("select count(*)::int n from public.messages where role='user'")).rows[0].n,0);
  await rpc(db,'morrow_finish_checkin',{p_id:id,p_lease:lease,p_status:'sent'});
  const history=await rpc<any>(db,'morrow_checkin_history',{p_owner:'alice'});
  assert.ok(history.checkins[0].provider_accepted_at);assert.equal(history.checkins[0].received_at,null);assert.equal(history.checkins[0].opened_at,null);
  assert.equal((await rpc<any>(db,'morrow_checkin_receipt',{p_owner:'bob',p_id:id,p_opened:true})).conversation,null);
  const receipt=await rpc<any>(db,'morrow_checkin_receipt',{p_owner:'alice',p_id:id,p_opened:true});assert.equal(receipt.conversation.id,route.conversation_id);
  assert.ok((await rpc<any>(db,'morrow_checkin_history',{p_owner:'alice'})).checkins[0].opened_at);
 }finally{await db.close();}
});

test('dispatcher rechecks cancellation after content generation before contacting the provider',async()=>{
 let cancelled=false,sends=0,finished:any;
 const dispatcher=createCheckinDispatcher({rpc:async<T>(name,args)=>{
  if(name==='morrow_finish_checkin')finished=args;
  return (name==='morrow_due_checkins'?{jobs:[{id:'job',lease:'lease',owner_id:'alice',companion_id:'c',devices:[{token:'fid',installation_id:'d'}]}]}:
   name==='morrow_authorize_checkin'?{allowed:!cancelled,ttl_seconds:60}:{}) as T;
 }},{send:async()=>{sends++;return 'sent';}},'secret',async()=>{cancelled=true;return {checkin_id:'job',conversation_id:'v'};});
 const response=await dispatcher(new Request('https://local.test',{method:'POST',headers:{Authorization:'Bearer secret'}}));
 assert.equal(response.status,200);assert.equal(sends,0);assert.equal(finished.p_status,'suppressed');
 assert.equal((await response.json()).delivery_confirmed,0);
});
