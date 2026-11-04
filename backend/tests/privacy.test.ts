import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database,rpc } from './database.ts';
import { createPrivacyApi,processErasure } from '../../supabase/functions/_shared/privacy.ts';
import type { Database } from '../../supabase/functions/_shared/database.ts';
import { FirebaseIdentityAdmin } from '../../supabase/functions/_shared/firebase_admin.ts';
import { GoogleServiceAccount } from '../../supabase/functions/_shared/google.ts';

async function setup(db:Awaited<ReturnType<typeof database>>,owner:string){
  await rpc(db,'morrow_bootstrap',{p_owner:owner});
  return (await rpc<any>(db,'morrow_save_companion',{p_owner:owner,p_name:'Lumi',p_style:'Gentle & warm',
    p_interests:[],p_response_length:.5,p_memory_enabled:false,p_retention_days:null})).companion;
}
test('RLS requires the exact Firebase project, filters expiry, and exports only owned data in pages',async()=>{
  const db=await database();
  try{
    const alice=await setup(db,'alice');await setup(db,'bob');
    await db.exec(`set role authenticated; set request.jwt.claims='{"sub":"alice","iss":"https://securetoken.google.com/another-project"}'`);
    assert.equal((await db.query('select * from public.companions')).rows.length,0);
    await db.exec(`set request.jwt.claims='{"sub":"alice","iss":"https://securetoken.google.com/morrow","firebase":{"sign_in_provider":"password"}}'`);
    assert.equal((await db.query('select * from public.companions')).rows.length,1);
    await db.exec('reset role');
    await db.query(`insert into public.memories(owner_id,companion_id,memory_key,category,title,content)
      select 'alice',$1,'manual.'||n,'preferences','Fact '||n,'User supplied fact '||n from generate_series(1,205) n`,[alice.id]);
    const first=await rpc<any>(db,'morrow_export_page',{p_owner:'alice',p_section:'memories'});
    assert.equal(first.rows.length,200);assert.ok(first.next_cursor);
    const second=await rpc<any>(db,'morrow_export_page',{p_owner:'alice',p_section:'memories',p_after:first.next_cursor});
    assert.equal(second.rows.length,5);assert.equal(second.next_cursor,null);
    assert.equal(new Set([...first.rows,...second.rows].map(x=>x.id)).size,205);
    assert.ok([...first.rows,...second.rows].every(x=>x.owner_id==='alice'&&!('search_vector' in x)));
    await assert.rejects(rpc(db,'morrow_export_page',{p_owner:'alice',p_section:'device_tokens'}),/invalid_input/);
    const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:'alice',p_companion:alice.id});
    await rpc(db,'morrow_set_conversation_retention',{p_owner:'alice',p_companion:alice.id,p_days:1});
    await db.query("update public.conversations set updated_at=now()-interval '2 days' where id=$1",[conversation.id]);
    await db.exec(`set role authenticated; set request.jwt.claims='{"sub":"alice","iss":"https://securetoken.google.com/morrow","firebase":{"sign_in_provider":"password"}}'`);
    assert.equal((await db.query('select * from public.conversations')).rows.length,0);
    await db.exec('reset role');
    await rpc(db,'morrow_guard_account',{p_owner:'alice',p_project:'morrow'});
    assert.equal((await db.query('select * from public.conversations')).rows.length,0);
  }finally{await db.close();}
});

test('erasure blocks access and resurrection, cascades private records, and resumes after Firebase failure',async()=>{
  const db=await database();
  try{
    const alice=await setup(db,'alice');await setup(db,'bob');
    await rpc(db,'morrow_set_learning',{p_owner:'alice',p_companion:alice.id,p_enabled:true});
    await rpc(db,'morrow_set_voice',{p_owner:'alice',p_companion:alice.id,p_enabled:true});
    await rpc(db,'morrow_create_conversation',{p_owner:'alice',p_companion:alice.id});
    await rpc(db,'morrow_register_device',{p_owner:'alice',p_installation:randomUUID(),p_token:'private-device-registration'});
    await rpc(db,'morrow_request_erasure',{p_owner:'alice'});
    await assert.rejects(rpc(db,'morrow_bootstrap',{p_owner:'alice'}),/account_deleted/);
    await assert.rejects(rpc(db,'morrow_guard_account',{p_owner:'alice',p_project:'morrow'}),/account_deleted/);
    await db.exec(`set role authenticated; set request.jwt.claims='{"sub":"alice","iss":"https://securetoken.google.com/morrow","firebase":{"sign_in_provider":"password"}}'`);
    assert.equal((await db.query('select * from public.companions')).rows.length,0);
    await db.exec('reset role');
    const databaseAdapter:Database={rpc:(name,args)=>rpc(db,name,args)};
    await assert.rejects(processErasure(databaseAdapter,{active:async()=>{},erase:async()=>{throw new Error('offline');}},'alice'));
    const failed=await rpc<any>(db,'morrow_account_status',{p_owner:'alice'});
    assert.equal(failed.status,'failed');assert.equal(failed.data_erased,true);
    assert.equal((await db.query("select * from public.profiles where user_id='bob'")).rows.length,1);
    for(const table of ['companions','conversations','memories','interaction_patterns','device_tokens','consent_events']){
      assert.equal((await db.query(`select * from public.${table} where owner_id='alice'`)).rows.length,0,table);
    }
    let deleted='';
    await processErasure(databaseAdapter,{active:async()=>{},erase:async uid=>{deleted=uid;}},'alice');
    assert.equal(deleted,'alice');
    assert.equal((await rpc<any>(db,'morrow_account_status',{p_owner:'alice'})).status,'complete');
    await assert.rejects(rpc(db,'morrow_bootstrap',{p_owner:'alice'}),/account_deleted/);
  }finally{await db.close();}
});

test('privacy API requires confirmation/recent identity and ignores requested owner IDs',async()=>{
  const observed:Record<string,unknown>[]=[];
  const now=Math.floor(Date.now()/1000);
  const create=(authTime:number)=>createPrivacyApi({projectId:'morrow',origins:[],verify:async()=>({uid:'alice',authTime}),
    admin:{active:async()=>{},erase:async()=>{}},db:{rpc:async<T>(name:string,args:Record<string,unknown>)=>{
      observed.push(args);return (name==='morrow_account_status'?{blocked:false,status:'active'}:
        name==='morrow_claim_erasure'?{job:null}:{rows:[],next_cursor:null}) as T;
    }}});
  const request=(body:unknown)=>new Request('https://local.test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  assert.equal((await create(now)(request({action:'request_account_erasure'}))).status,400);
  assert.equal((await create(now-1000)(request({action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'}))).status,401);
  assert.equal((await create(now)(request({action:'export_data',section:'profile',owner_id:'bob'}))).status,200);
  assert.ok(observed.every(x=>x.p_owner==='alice'));
});

test('Firebase admin checks disabled/revoked users and fails closed when credentials are missing',async()=>{
  let disabled=false,validSince='100';
  const account={projectId:'morrow',token:async()=> 'server-access'} as unknown as GoogleServiceAccount;
  const admin=new FirebaseIdentityAdmin(account,async()=>Response.json({users:[{localId:'alice',disabled,validSince}]}));
  await admin.active({uid:'alice',authTime:200},true);
  disabled=true;await assert.rejects(admin.active({uid:'alice',authTime:200},true));
  disabled=false;validSince='300';await assert.rejects(admin.active({uid:'alice',authTime:200},true));
  await assert.rejects(new FirebaseIdentityAdmin(new GoogleServiceAccount('','morrow')).active({uid:'alice',authTime:200}));
});

test('database RLS denies existing guest tokens and missing providers, and allows registered owners',async()=>{
 const db=await database();try{
  await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
  await db.exec('set role authenticated');
  for(const provider of [undefined,'anonymous','password','google.com']){
   const claims={sub:'alice',iss:'https://securetoken.google.com/morrow',...(provider?{firebase:{sign_in_provider:provider}}:{})};
   await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify(claims)]);
   const visible=await db.query('select user_id from public.profiles');
   assert.equal(visible.rows.length,provider==='password'||provider==='google.com'?1:0);
  }
 }finally{await db.close();}
});
