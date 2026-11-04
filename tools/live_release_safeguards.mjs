// Deployed account/reporting/billing checks. No model requests or real purchases.
// Only fictional identities created by this run are seeded and erased.
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile,writeFile,unlink} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
const config=JSON.parse(await readFile('config/development.json','utf8'));
const cli=process.env.AI_COMPANION_SUPABASE_CLI;
assert.ok(cli&&path.isAbsolute(cli),'Supply the owning Supabase CLI executable path.');
const users=[],checks=[];let stage='schema';
const sqlPath=path.resolve(`.cache/release-check-${randomBytes(8).toString('hex')}.sql`);
function passed(check){checks.push({check,passed:true});console.log(check);}
async function query(sql,readonly=true){
 await writeFile(sqlPath,sql);
 const output=execFileSync(cli,['db','query','--remote=rvokidwyzwygpzzkpqck','--file',sqlPath,'--output','json',...(readonly?['--read-only']:['--yes'])],
  {encoding:'utf8',windowsHide:true,timeout:45000,stdio:['ignore','pipe','pipe']});
 return JSON.parse(output.slice(output.indexOf('{'))).rows;
}
async function firebase(action,body){
 const r=await fetch(`https://identitytoolkit.googleapis.com/v1/${action}?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const value=await r.json();assert.ok(r.ok,`Firebase ${action}: HTTP ${r.status}`);return value;
}
async function api(user,body,endpoint='companion-api',expected=200){
 const r=await fetch(`${config.SUPABASE_URL}/functions/v1/${endpoint}`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  Authorization:`Bearer ${user.token}`,'Content-Type':'application/json',Origin:'http://localhost:52100'},
  body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
 const result=await r.json();assert.equal(r.status,expected,`${endpoint}/${body.action}: ${result.code??r.status}`);return result;
}
async function account(){
 const suffix=randomBytes(9).toString('hex'),value=await firebase('accounts:signUp',{
  email:`release-check-${suffix}@example.invalid`,password:`Aa!9${randomBytes(24).toString('base64url')}`,returnSecureToken:true});
 assert.match(value.localId,/^[A-Za-z0-9_-]+$/);
 const user={uid:value.localId,token:value.idToken};users.push(user);
 await api(user,{action:'bootstrap'});
 await api(user,{action:'save_personal_profile',username:`qa_${suffix}`,preferred_name:'Fictional Tester',timezone:'Africa/Kampala'});
 await api(user,{action:'save_introduction',age_group:'25_34',language:'en',timezone:'Africa/Kampala'});
 return user;
}
try{
 const [schema]=await query(`select
 (select count(*) from pg_class where relnamespace='public'::regnamespace and relkind='r' and relname in
 ('profiles','companions','conversations','turn_requests','messages','memories','memory_tombstones','memory_jobs','interaction_patterns',
 'notification_preferences','device_tokens','scheduled_checkins','voice_usage','identity_configuration','account_deletions','consent_events',
 'content_reports','billing_configuration','billing_accounts','subscriptions','billing_usage','review_configuration','review_guest_sessions')) as tables,
 (select count(*) from pg_class where relnamespace='public'::regnamespace and relkind='r' and not relrowsecurity) as unprotected_tables,
 (select count(*) from pg_proc where pronamespace='public'::regnamespace and left(proname,7)='morrow_') as functions,
 (select count(*) from pg_proc where pronamespace='public'::regnamespace and left(proname,7)='morrow_'
 and proname not in ('morrow_authenticated_owner','morrow_visible_conversation')
 and (has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute'))) as unsafe_write_functions,
 (select sales_enabled or enforcement_enabled from public.billing_configuration where singleton) as billing_enabled;`);
 assert.equal(Number(schema.tables),23);assert.equal(Number(schema.unprotected_tables),0);
 assert.equal(Number(schema.unsafe_write_functions),0);assert.equal(schema.billing_enabled,false);
 passed(`Live schema: ${schema.tables} RLS tables, ${schema.functions} functions; write RPCs restricted, billing off`);
 stage='synthetic accounts';const first=await account(),second=await account();
 const saved=await api(first,{action:'save_companion',name:'Lumi',style:'Gentle & warm',interests:[],response_length:.5,memory_enabled:false,retention_days:null});
 const {conversation}=await api(first,{action:'create_conversation',companion_id:saved.companion.id,title:'Disposable release safeguards'});
 assert.match(conversation.id,/^[a-f0-9-]{36}$/i);
 stage='seed fictional completed reply without AI';const request=randomUUID();
 await query(`do $$ declare claim jsonb; begin
 claim:=public.morrow_access_begin_turn('${first.uid}','${conversation.id}','${request}','A fictional release test.');
 perform public.morrow_complete_turn('${first.uid}','${request}',(claim->>'lease')::uuid,'A seeded fictional assistant reply for reporting checks.');
 end $$;`,false);
 const {messages}=await api(first,{action:'messages',conversation_id:conversation.id});
 const message=messages.find(m=>m.role==='assistant');assert.ok(message);
 stage='owned reporting';const body={action:'report_message',message_id:message.id,request_id:randomUUID(),reason:'inaccurate',details:'A disposable fictional report.'};
 const receipt=await api(first,body);assert.deepEqual(await api(first,body),receipt);
 await api(second,body,'companion-api',404);
 const exported=await api(first,{action:'export_data',section:'reports'},'privacy');
 assert.equal(exported.rows.length,1);assert.equal(exported.rows[0].message_snapshot,message.content);
 assert.equal((await api(second,{action:'export_data',section:'reports'},'privacy')).rows.length,0);
 passed('Owned reply report, idempotent retry, foreign-account denial and private export');
 stage='disabled purchases';
 const status=await api(first,{action:'billing_status',premium:true,owner_id:second.uid},'billing');
 assert.equal(status.mode,'free_testing');assert.equal(status.available,false);assert.equal(status.premium,false);
 const denial=await api(first,{action:'billing_verify',purchase_token:'fictional-token',premium:true},'billing',503);
 assert.equal(denial.code,'billing_unavailable');
 passed('Deployed billing remains free; client premium flags cannot grant access or start purchases');
}catch(error){checks.push({check:stage,passed:false,error:error.message});process.exitCode=1;}
finally{
 for(const user of users){try{
  await api(user,{action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'},'privacy',202);
  let complete=false;for(let n=0;n<20;n++){
   if((await api(user,{action:'erasure_status'},'privacy')).status==='complete'){complete=true;break;}
   await new Promise(r=>setTimeout(r,1000));
  }
  assert.ok(complete,'Erasure did not complete in the test window.');
  const [left]=await query(`select (select count(*) from public.profiles where user_id='${user.uid}')+
   (select count(*) from public.content_reports where owner_id='${user.uid}')+
   (select count(*) from public.billing_accounts where owner_id='${user.uid}') as remaining;`);
  assert.equal(Number(left.remaining),0);
  passed('Disposable identity erased; no owned profile/report/billing account remains');
 }catch(error){checks.push({check:'Disposable identity cleanup',passed:false,test_uid:user.uid,error:error.message});process.exitCode=1;}}
 await unlink(sqlPath).catch(()=>{});
 const report={checked_at_utc:new Date().toISOString(),ai_requests:0,purchases:0,temporary_identities_created:users.length,checks};
 await writeFile('.cache/live-release-safeguards.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
}
