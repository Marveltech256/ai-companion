import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database,rpc } from './database.ts';
import { createCheckinDispatcher,FirebasePush } from '../../supabase/functions/_shared/checkins.ts';
import type { GoogleServiceAccount } from '../../supabase/functions/_shared/google.ts';

test('check-ins require opt-in, timezone, allowed hours and never exceed one per local day',async()=>{
  const db=await database();
  try{
    await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
    const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Lumi',p_style:'Playful',
      p_interests:[],p_response_length:.5,p_memory_enabled:false,p_retention_days:null});
    const args={p_owner:'alice',p_companion:companion.id,p_checkins:true,p_suggestions:false,p_birthdays:false,
      p_timezone:'Europe/London',p_local_minute:1140,p_weekdays:[0,1,2,3,4,5,6],p_quiet_start:1320,p_quiet_end:480};
    await assert.rejects(rpc(db,'morrow_save_notification_preferences',{...args,p_timezone:null}),/invalid_input/);
    await assert.rejects(rpc(db,'morrow_save_notification_preferences',{...args,p_local_minute:1380}),/invalid_input/);
    await assert.rejects(rpc(db,'morrow_save_notification_preferences',{...args,p_owner:'bob'}),/not_found/);
    await rpc(db,'morrow_save_notification_preferences',args);
    const now=new Date();now.setUTCDate(now.getUTCDate()+1);now.setUTCHours(19,5,0,0);
    // November London is UTC. Tests use an explicit fixed winter date after token registration.
    const day=`${now.getUTCFullYear()+1}-11-02`;
    await rpc(db,'morrow_register_device',{p_owner:'alice',p_installation:randomUUID(),p_token:'test-device-token-1234567890'});
    // Keep the fixture device current at the future deterministic schedule date.
    await db.query('update public.device_tokens set updated_at=$1',[`${day}T18:00:00Z`]);
    assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:`${day}T07:00:00Z`})).jobs.length,0);
    const jobs=await rpc<any>(db,'morrow_due_checkins',{p_now:`${day}T19:05:00Z`});
    assert.equal(jobs.jobs.length,1);
    assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:`${day}T19:06:00Z`})).jobs.length,0);
    await rpc(db,'morrow_save_notification_preferences',{...args,p_checkins:false});
    assert.equal((await rpc<any>(db,'morrow_authorize_checkin',{
      p_id:jobs.jobs[0].id,p_lease:jobs.jobs[0].lease})).allowed,false);
    assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:`${day}T22:05:00Z`})).jobs.length,0);
  }finally{await db.close();}
});

test('dispatcher rejects callers without its secret and rechecks consent before sending',async()=>{
  let sends=0;
  const dispatcher=createCheckinDispatcher({rpc:async<T>(name:string)=>{
    return (name==='morrow_due_checkins'?{jobs:[{id:'job',lease:'lease',owner_id:'alice',devices:[{token:'private',installation_id:'device'}]}]}:
      name==='morrow_authorize_checkin'?{allowed:false}:{ok:true}) as T;
  }},{send:async()=>{sends++;return 'sent';}},'server-only-secret');
  assert.equal((await dispatcher(new Request('https://local.test',{method:'POST'}))).status,401);
  assert.equal((await dispatcher(new Request('https://local.test',{method:'POST',headers:{Authorization:'Bearer server-only-secret'}}))).status,200);
  assert.equal(sends,0);
});

test('DST repeated hours cannot duplicate a check-in and push expiry stops at quiet hours',async()=>{
  const db=await database();
  try{
    await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
    const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Lumi',p_style:'Playful',
      p_interests:[],p_response_length:.5,p_memory_enabled:false,p_retention_days:null});
    await rpc(db,'morrow_save_notification_preferences',{p_owner:'alice',p_companion:companion.id,
      p_checkins:true,p_suggestions:false,p_birthdays:false,p_timezone:'America/New_York',
      p_local_minute:90,p_weekdays:[0,1,2,3,4,5,6],p_quiet_start:180,p_quiet_end:30});
    const year=new Date().getUTCFullYear()+1;
    const first=new Date(Date.UTC(year,10,1));
    const sunday=1+(7-first.getUTCDay())%7;
    const day=`${year}-11-${String(sunday).padStart(2,'0')}`;
    await rpc(db,'morrow_register_device',{p_owner:'alice',p_installation:randomUUID(),p_token:'test-fid-for-dst-12345678'});
    await db.query('update public.device_tokens set updated_at=$1',[`${day}T05:00:00Z`]);
    assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:`${day}T05:35:00Z`})).jobs.length,1);
    assert.equal((await rpc<any>(db,'morrow_due_checkins',{p_now:`${day}T06:35:00Z`})).jobs.length,0);
    const ttl=await rpc<any>(db,'morrow_notification_ttl',{p_now:`${year}-11-10T21:59:30Z`,
      p_timezone:'Europe/London',p_start:1320,p_end:480});
    assert.equal(ttl,30);
  }finally{await db.close();}
});

test('a permitted check-in uses the FCM registration token field, bounded TTL, and no private lock-screen facts',async()=>{
  let message:any,finished:any;
  const account={projectId:'morrow',token:async()=> 'server-token'} as unknown as GoogleServiceAccount;
  const sender=new FirebasePush(account,async(url,init)=>{
    assert.equal(String(url),'https://fcm.googleapis.com/v1/projects/morrow/messages:send');
    message=JSON.parse(init!.body as string).message;return Response.json({name:'sent-message'});
  });
  const dispatcher=createCheckinDispatcher({rpc:async<T>(name:string,args:Record<string,unknown>)=>{
    if(name==='morrow_finish_checkin')finished=args;
    return (name==='morrow_due_checkins'?{jobs:[{id:'daily-job',lease:'lease',owner_id:'alice',devices:[{token:'registered-fid',installation_id:'device'}]}]}:
      name==='morrow_authorize_checkin'?{allowed:true,ttl_seconds:30}:{ok:true}) as T;
  }},sender,'server-only-secret');
  const response=await dispatcher(new Request('https://local.test',{method:'POST',headers:{Authorization:'Bearer server-only-secret'}}));
  assert.equal(response.status,200);assert.equal((await response.json()).sent,1);
  assert.equal(message.token,'registered-fid');assert.equal(message.fid,undefined);
  assert.ok(parseInt(message.android.ttl,10)>0&&parseInt(message.android.ttl,10)<=30);
  assert.deepEqual(message.data,{screen:'conversation'});
  assert.ok(!JSON.stringify(message).includes('alice'));
  assert.equal(finished.p_status,'sent');
});
