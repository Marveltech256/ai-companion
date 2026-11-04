import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {database,rpc} from './database.ts';
import {decodeSubscription,PurchaseCipher,purchaseHash} from '../../supabase/functions/_shared/play_billing.ts';
import {BillingService,createBillingApi} from '../../supabase/functions/_shared/billing_api.ts';
import {createBillingNotifications,verifyBillingPush} from '../../supabase/functions/_shared/billing_notifications.ts';
import {ApiError} from '../../supabase/functions/_shared/errors.ts';
import {refreshingAccessDatabase} from '../../supabase/functions/_shared/billing_access.ts';

test('a stale entitlement refresh retries only the denied claim before any generation and never grants on store failure',async()=>{
 let claims=0,refreshes=0;const args={p_owner:'alice',p_request:randomUUID()};
 const db={async rpc<T>(name:string,body:Record<string,unknown>):Promise<T>{
  assert.deepEqual(body,args);claims++;if(claims===1)throw new ApiError(403,'subscription_required','Expired cached access.');
  return {status:'running'} as T;
 }};
 assert.equal(refreshingAccessDatabase(db),db);
 const wrapped=refreshingAccessDatabase(db,async owner=>{assert.equal(owner,'alice');refreshes++;});
 assert.deepEqual(await wrapped.rpc('morrow_access_begin_turn',args),{status:'running'});assert.equal(claims,2);assert.equal(refreshes,1);
 claims=0;
 await assert.rejects(refreshingAccessDatabase(db,async()=>{throw new ApiError(503,'billing_unavailable','Store offline.');})
  .rpc('morrow_access_voice',args),/Store offline/);assert.equal(claims,1);
 claims=0;refreshes=0;
 await assert.rejects(wrapped.rpc('morrow_messages',args),/Expired cached/);assert.equal(refreshes,0);assert.equal(claims,1);
});

async function account(db:any,owner='alice'){
 await rpc(db,'morrow_bootstrap',{p_owner:owner});
 const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:owner,p_name:'Lumi',p_style:'Gentle & warm',p_interests:[],p_response_length:.5,p_memory_enabled:true,p_retention_days:null});
 const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:owner,p_companion:companion.id});
 return {companion,conversation};
}
async function configure(db:any,enforce=false){await db.exec(`update public.billing_configuration set sales_enabled=true,enforcement_enabled=${enforce},
 monthly_product_id='monthly',monthly_base_plan_id='monthly-base',intro_days=1,free_daily_messages=1,premium_daily_messages=2,free_daily_voice=1,premium_daily_voice=2`);}
async function subscription(db:any,owner='alice',extra:Record<string,unknown>={}){
 const s=await rpc<any>(db,'morrow_billing_status',{p_owner:owner});
 return rpc<any>(db,'morrow_apply_subscription',{p_owner:owner,p_account_ref:s.account_ref,p_token_hash:'a'.repeat(64),p_linked_hash:null,
  p_encrypted_token:'encrypted-test-token',p_product:'monthly',p_base_plan:'monthly-base',p_state:'active',
  p_expires:new Date(Date.now()+86400000).toISOString(),p_acknowledged:true,p_auto_renew:true,p_verified_at:new Date().toISOString(),...extra});
}

test('reply reports are owned, assistant-only, idempotent, private and erased with the account',async()=>{
 const db=await database();try{
  const {conversation}=await account(db);await account(db,'bob');
  const request=randomUUID(),claim=await rpc<any>(db,'morrow_begin_turn',{p_owner:'alice',p_conversation:conversation.id,p_request:request,p_content:'A fictional test.'});
  await rpc(db,'morrow_complete_turn',{p_owner:'alice',p_request:request,p_lease:claim.lease,p_content:'A synthetic assistant answer.'});
  const {messages}=await rpc<any>(db,'morrow_messages',{p_owner:'alice',p_conversation:conversation.id});
  const assistant=messages.find((m:any)=>m.role==='assistant'),user=messages.find((m:any)=>m.role==='user');
  const args={p_owner:'alice',p_request:randomUUID(),p_message:assistant.id,p_reason:'unsafe',p_details:'A fictional review note.'};
  await assert.rejects(rpc(db,'morrow_report_message',{...args,p_owner:'bob'}),/not_found/);
  await assert.rejects(rpc(db,'morrow_report_message',{...args,p_message:user.id}),/not_found/);
  const first=await rpc(db,'morrow_report_message',args);assert.deepEqual(await rpc(db,'morrow_report_message',args),first);
  await assert.rejects(rpc(db,'morrow_report_message',{...args,p_details:'changed'}),/request_conflict/);
  assert.equal((await db.query('select count(*)::int n from public.content_reports')).rows[0].n,1);
  await db.exec('set role authenticated');
  await assert.rejects(db.query('select * from public.content_reports'),/permission denied/);await db.exec('reset role');
  assert.equal((await rpc<any>(db,'morrow_report_export',{p_owner:'bob'})).rows.length,0);
  const exported=await rpc<any>(db,'morrow_report_export',{p_owner:'alice'});assert.equal(exported.rows[0].message_snapshot,assistant.content);
  await db.exec("delete from public.profiles where user_id='alice'");
  assert.equal((await db.query('select count(*)::int n from public.content_reports')).rows[0].n,0);
 }finally{await db.close();}
});

test('billing stays free by default and optional usage wrappers preserve existing turns',async()=>{
 const db=await database();try{
  const {conversation}=await account(db);
  assert.deepEqual(await rpc(db,'morrow_billing_status',{p_owner:'alice'}),{mode:'free_testing',available:false,enforced:false,premium:false});
  const claim=await rpc<any>(db,'morrow_access_begin_turn',{p_owner:'alice',p_conversation:conversation.id,p_request:randomUUID(),p_content:'Hello'});
  assert.equal(claim.status,'running');
  assert.equal((await db.query('select count(*)::int n from public.billing_usage')).rows[0].n,0);
  assert.equal((await db.query('select count(*)::int n from public.billing_accounts')).rows[0].n,0);
  await assert.rejects(db.exec('update public.billing_configuration set sales_enabled=true'),/check constraint/);
  const permissions=await db.query<{bad:number}>(`select count(*)::int bad from pg_proc where pronamespace='public'::regnamespace
   and proname like 'morrow_%' and proname not in ('morrow_authenticated_owner','morrow_visible_conversation')
   and (has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute'))`);
  assert.equal(permissions.rows[0].bad,0);
 }finally{await db.close();}
});

test('entitlements require acknowledgement, match the account and cannot be resurrected by stale updates',async()=>{
 const db=await database();try{
  await account(db);await account(db,'bob');await configure(db,true);
  const first=await subscription(db,'alice',{p_acknowledged:false});assert.equal(first.premium,false);
  assert.equal((await subscription(db)).premium,true);
  const bob=await rpc<any>(db,'morrow_billing_status',{p_owner:'bob'});
  await assert.rejects(subscription(db,'bob',{p_account_ref:bob.account_ref}),/purchase_conflict/);
  const later=new Date(Date.now()+1000).toISOString();
  const revoked=await rpc<any>(db,'morrow_invalidate_subscription',{p_owner:'alice',p_hash:'a'.repeat(64),p_verified_at:later});assert.equal(revoked.premium,false);
  assert.equal((await subscription(db,'alice',{p_verified_at:new Date().toISOString()})).premium,false);
  assert.equal((await subscription(db,'alice',{p_verified_at:new Date(Date.now()+2000).toISOString()})).premium,false);
  const exported=await rpc<any>(db,'morrow_billing_export',{p_owner:'alice',p_section:'subscriptions'});
  assert.ok(!JSON.stringify(exported).includes('encrypted-test-token'));assert.ok(!JSON.stringify(exported).includes('token_hash'));
 }finally{await db.close();}
});

test('daily quotas are atomic with the claim, retries do not spend twice, and expired access cannot generate',async()=>{
 const db=await database();try{
  const {conversation}=await account(db);await configure(db,true);
  const args={p_owner:'alice',p_conversation:conversation.id,p_request:randomUUID(),p_content:'First message'};
  const claim=await rpc<any>(db,'morrow_access_begin_turn',args);
  await rpc(db,'morrow_fail_turn',{p_owner:'alice',p_request:args.p_request,p_lease:claim.lease});
  const retry=await rpc<any>(db,'morrow_access_begin_turn',args);
  await rpc(db,'morrow_complete_turn',{p_owner:'alice',p_request:args.p_request,p_lease:retry.lease,p_content:'Saved answer'});
  assert.equal((await rpc<any>(db,'morrow_access_begin_turn',args)).status,'completed');
  await assert.rejects(rpc(db,'morrow_access_begin_turn',{...args,p_request:randomUUID(),p_content:'Over quota'}),/usage_limit/);
  assert.equal((await db.query("select count(*)::int n from public.messages where role='user'")).rows[0].n,1);
  assert.equal((await db.query("select count(*)::int n from public.billing_usage where kind='chat'")).rows[0].n,1);
  await db.exec("update public.billing_accounts set intro_started_at=now()-interval '3 days'");
  await assert.rejects(rpc(db,'morrow_access_begin_turn',{...args,p_request:randomUUID(),p_content:'Expired intro'}),/subscription_required/);
  await subscription(db);
  assert.equal((await rpc<any>(db,'morrow_access_begin_turn',{...args,p_request:randomUUID(),p_content:'Premium limit'})).status,'running');
 }finally{await db.close();}
});

const purchase=(overrides:any={})=>({subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',acknowledgementState:'ACKNOWLEDGEMENT_STATE_PENDING',
 externalAccountIdentifiers:{obfuscatedExternalAccountId:'bound-account'},lineItems:[{productId:'monthly',offerDetails:{basePlanId:'monthly-base'},
  expiryTime:new Date(Date.now()+86400000).toISOString(),autoRenewingPlan:{autoRenewEnabled:true}}],...overrides});
test('Google subscription decoding rejects a different account/plan and preserves lifecycle states',()=>{
 assert.throws(()=>decodeSubscription(purchase(),'other-account','monthly','monthly-base'),/different companion account/);
 assert.throws(()=>decodeSubscription(purchase(),'bound-account','other-product','monthly-base'),/plan does not match/);
 for(const [google,state] of [['SUBSCRIPTION_STATE_ACTIVE','active'],['SUBSCRIPTION_STATE_IN_GRACE_PERIOD','grace'],
  ['SUBSCRIPTION_STATE_CANCELED','canceled'],['SUBSCRIPTION_STATE_ON_HOLD','hold'],['SUBSCRIPTION_STATE_EXPIRED','expired']]){
  assert.equal(decodeSubscription(purchase({subscriptionState:google}),'bound-account','monthly','monthly-base').state,state);
 }
});
test('purchase tokens are encrypted with owner/hash binding and never returned by the billing API',async()=>{
 const cipher=new PurchaseCipher('A'.repeat(43)),hash=await purchaseHash('synthetic-purchase-token');
 const encrypted=await cipher.encrypt('synthetic-purchase-token','alice',hash);
 assert.ok(!encrypted.includes('synthetic-purchase-token'));assert.equal(await cipher.decrypt(encrypted,'alice',hash),'synthetic-purchase-token');
 await assert.rejects(cipher.decrypt(encrypted,'bob',hash));
 const calls:{name:string;args:any}[]=[];let acknowledged=false;
 const deps={origins:[],verify:async()=>({uid:'alice'}),db:{rpc:async<T>(name:string,args:any)=>{
  calls.push({name,args});if(name==='morrow_billing_status')return {available:true,account_ref:'bound-account',product_id:'monthly',base_plan_id:'monthly-base'} as T;
  if(name==='morrow_apply_subscription'){assert.ok(acknowledged);assert.equal(args.p_owner,'alice');assert.equal(args.p_state,'active');assert.notEqual(args.p_encrypted_token,'synthetic-purchase-token');return {mode:'premium',premium:true} as T;}
  return {} as T;
 }}};
 const service=new BillingService(deps,{configured:true,read:async()=>purchase(),acknowledge:async()=>{acknowledged=true;}},cipher,true);
 const api=createBillingApi(service);
 const response=await api(new Request('https://local.test',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({action:'billing_verify',purchase_token:'synthetic-purchase-token',owner:'bob',premium:true})}));
 assert.equal(response.status,200);const output=await response.text();assert.ok(!output.includes('synthetic-purchase-token'));assert.equal(calls.filter(c=>c.name==='morrow_apply_subscription').length,1);
 acknowledged=false;
 const broken=new BillingService(deps,{configured:true,read:async()=>purchase(),acknowledge:async()=>{throw new Error('offline');}},cipher,true);
 await assert.rejects(broken.verify('alice','token'));assert.equal(calls.filter(c=>c.name==='morrow_apply_subscription').length,1);
});
test('billing notifications require authenticated delivery and re-read Google rather than trusting notification claims',async()=>{
 await assert.rejects(verifyBillingPush(new Request('https://local.test'),'sender@example.invalid','audience'),/Authentication/);
 let googleReads=0,applied=0;
 const service=new BillingService({origins:[],verify:async()=>({uid:'unused'}),db:{rpc:async<T>(name:string)=>{
  if(name==='morrow_subscription_owner')return {owner:'alice'} as T;
  if(name==='morrow_billing_status')return {available:true,account_ref:'bound-account',product_id:'monthly',base_plan_id:'monthly-base'} as T;
  if(name==='morrow_apply_subscription'){applied++;return {premium:false} as T;}return {} as T;
 }}},{configured:true,read:async()=>{googleReads++;return purchase({subscriptionState:'SUBSCRIPTION_STATE_ON_HOLD'});},acknowledge:async()=>{}},new PurchaseCipher('A'.repeat(43)),true);
 const body={message:{data:btoa(JSON.stringify({packageName:'com.aipersonalcompanion',subscriptionNotification:{purchaseToken:'synthetic-token',notificationType:2},premium:true}))}};
 const handler=createBillingNotifications(service,async()=>{});
 assert.equal((await handler(new Request('https://local.test',{method:'POST',body:JSON.stringify(body)}))).status,204);
 assert.equal(googleReads,1);assert.equal(applied,1);
 const denied=createBillingNotifications(service,async()=>{throw new ApiError(401,'unauthenticated','Authentication required');});
 assert.equal((await denied(new Request('https://local.test',{method:'POST',body:JSON.stringify(body)}))).status,401);assert.equal(googleReads,1);
});
