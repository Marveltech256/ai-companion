// Only isolated, fictional review identities. No provider generations or purchases.
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile,writeFile,unlink} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
const config=JSON.parse(await readFile('config/development.json','utf8'));
const code=(await readFile('config/PLAY_REVIEW_ACCESS.private.txt','utf8')).match(/^Access code: ([A-Za-z0-9_-]{43})$/m)?.[1];assert.ok(code);
const cli=process.env.AI_COMPANION_SUPABASE_CLI;assert.ok(cli&&path.isAbsolute(cli));
const sqlFile=path.resolve('.cache/live-review-guest-check.sql');
const users=[],checks=[];let stage='review availability';
function passed(check){checks.push({check,passed:true});console.log(check);}
async function query(sql){await writeFile(sqlFile,sql);const text=execFileSync(cli,['db','query','--remote=rvokidwyzwygpzzkpqck','--file',sqlFile,'--yes','--output','json'],{encoding:'utf8',windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:45000});return JSON.parse(text.slice(text.indexOf('{'))).rows;}
async function request(endpoint,body,user,expected=200){
 const r=await fetch(`${config.SUPABASE_URL}/functions/v1/${endpoint}`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  'Content-Type':'application/json',Origin:'http://localhost:52100',...(user?{Authorization:`Bearer ${user.token}`}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
 const value=await r.json();assert.equal(r.status,expected,`${endpoint}/${body.action}: ${value.code??r.status}`);return value;
}
async function exchange(custom){
 const r=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(config.FIREBASE_WEB_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:custom,returnSecureToken:true}),signal:AbortSignal.timeout(20000)});
 const value=await r.json();assert.equal(r.status,200,`Firebase custom-token exchange: ${value.error?.message?.split(' : ')[0]??r.status}`);
 const claims=JSON.parse(Buffer.from(value.idToken.split('.')[1],'base64url').toString('utf8'));
 assert.match(claims.sub,/^review_[0-9a-f-]{36}$/);
 assert.equal(claims.review_guest,true);assert.equal(claims.firebase.sign_in_provider,'custom');
 return{uid:claims.sub,token:value.idToken,refreshToken:value.refreshToken};
}
async function enter(){
 const value=await request('review-access',{action:'enter',access_code:code,owner_id:'forged-victim'});
 const user=await exchange(value.custom_token);users.push(user);return user;
}
async function bootstrap(user){
 const result=await request('companion-api',{action:'bootstrap'},user);assert.equal(result.profile.user_id,user.uid);
 await request('companion-api',{action:'save_personal_profile',username:`review_${randomBytes(9).toString('hex')}`,preferred_name:'Fictional Reviewer',timezone:'Africa/Kampala'},user);
 await request('companion-api',{action:'save_introduction',age_group:'25_34',language:'en',timezone:'Africa/Kampala'},user);
}
try{
 assert.deepEqual(await request('review-access',{action:'status'}),{enabled:true});
 const wrong=await request('review-access',{action:'enter',access_code:'incorrect-review-code'},null,401);assert.equal(wrong.code,'invalid_review_code');
 passed('Live review availability is enabled; a wrong code is denied');
 stage='Firebase custom identities';const first=await enter(),second=await enter();assert.notEqual(first.uid,second.uid);
 const refreshed=await fetch(`https://securetoken.googleapis.com/v1/token?key=${encodeURIComponent(config.FIREBASE_WEB_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
  body:new URLSearchParams({grant_type:'refresh_token',refresh_token:first.refreshToken}),signal:AbortSignal.timeout(20000)});
 const refreshedBody=await refreshed.json();assert.equal(refreshed.status,200);
 const refreshedClaims=JSON.parse(Buffer.from(refreshedBody.id_token.split('.')[1],'base64url').toString('utf8'));
 assert.equal(refreshedClaims.sub,first.uid);assert.equal(refreshedClaims.review_guest,true);assert.ok(refreshedClaims.review_version);
 first.token=refreshedBody.id_token;first.refreshToken=refreshedBody.refresh_token;
 await bootstrap(first);await bootstrap(second);
 passed('Review code creates separate Firebase custom identities and owned profiles; Firebase refresh preserves the scoped review claims');
 stage='owned conversation';const saved=await request('companion-api',{action:'save_companion',name:'Lumi',style:'Gentle & warm',interests:[],response_length:.5,memory_enabled:false,retention_days:null},first);
 await request('companion-api',{action:'activate_friend_mode',companion_id:saved.companion.id,consent:true},first);
 const {conversation}=await request('companion-api',{action:'create_conversation',companion_id:saved.companion.id,title:'Disposable review guest check'},first);
 assert.match(conversation.id,/^[0-9a-f-]{36}$/);
 await request('companion-api',{action:'messages',conversation_id:conversation.id},second,404);
 const id=randomUUID();
 await query(`do $$ declare claim jsonb; begin
  claim:=public.morrow_access_begin_turn('${first.uid}','${conversation.id}','${id}','A fictional guest test.');
  perform public.morrow_complete_turn('${first.uid}','${id}',(claim->>'lease')::uuid,'A synthetic saved guest reply.');
 end $$;`);
 const stream=await fetch(`${config.SUPABASE_URL}/functions/v1/conversation-turn`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  Authorization:`Bearer ${first.token}`,'Content-Type':'application/json'},body:JSON.stringify({conversation_id:conversation.id,request_id:id,content:'A fictional guest test.'}),signal:AbortSignal.timeout(30000)});
 assert.equal(stream.status,200);const text=await stream.text();assert.match(text,/A synthetic saved guest reply/);assert.match(text,/"type":"done"/);
 passed('Owned history and normal streaming replay work; another guest cannot read the conversation (seeded reply, no model call)');
 stage='code renewal';const renewed=await request('review-access',{action:'enter',access_code:code,renew:true,owner_id:second.uid},first);
 const restored=await exchange(renewed.custom_token);assert.equal(restored.uid,first.uid);first.token=restored.token;
 assert.equal((await request('companion-api',{action:'messages',conversation_id:conversation.id},first)).messages.length,2);
 passed('Reconfirming the code preserves the same guest identity and saved history; a forged owner is ignored');
 stage='individual revocation';
 try{
  await query(`update public.review_guest_sessions set version=gen_random_uuid() where owner_id='${first.uid}';`);
  const denied=await request('companion-api',{action:'bootstrap'},first,401);assert.equal(denied.code,'review_access_ended');
  await request('companion-api',{action:'bootstrap'},second);
 }finally{await query(`update public.review_guest_sessions set version=(select version from public.review_configuration where singleton) where owner_id='${first.uid}';`);}
 passed('Revoking one guest blocks its live API access without affecting the other guest');
}catch(error){checks.push({check:stage,passed:false,error:error.message});process.exitCode=1;}
finally{
 for(const user of users){try{
  await request('privacy',{action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'},user,202);
  let complete=false;for(let n=0;n<20;n++){
   if((await request('privacy',{action:'erasure_status'},user)).status==='complete'){complete=true;break;}await new Promise(r=>setTimeout(r,1000));
  }
  assert.ok(complete,'Review account erasure did not complete.');
  const [left]=await query(`select (select count(*) from public.profiles where user_id='${user.uid}')+
   (select count(*) from public.review_guest_sessions where owner_id='${user.uid}') as remaining;`);assert.equal(Number(left.remaining),0);
  passed('Disposable reviewer profile, session registry and Firebase account erased through the normal privacy flow');
 }catch(error){checks.push({check:'Disposable reviewer cleanup',passed:false,test_uid:user.uid,error:error.message});process.exitCode=1;}}
 await unlink(sqlFile).catch(()=>{});
 const report={checked_at_utc:new Date().toISOString(),temporary_review_identities:users.length,ai_requests:0,purchases:0,seeded_reply:true,checks};
 await writeFile('.cache/live-review-guest-test.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
}
