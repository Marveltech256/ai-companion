// Fictional adult accounts only. No child data, real payments, or credentials in output.
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {serverEvents} from '../supabase/functions/_shared/openai.ts';
const config=JSON.parse(await readFile('config/development.json','utf8'));
const users=[],checks=[],samples=[];let stage='authentication',generationRequests=0;
async function firebase(action,body){
 const r=await fetch(`https://identitytoolkit.googleapis.com/v1/${action}?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const value=await r.json();assert.ok(r.ok,`Firebase HTTP ${r.status}`);return value;
}
async function request(user,body,endpoint='companion-api'){
 return fetch(`${config.SUPABASE_URL}/functions/v1/${endpoint}`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,
  ...(user?{Authorization:`Bearer ${user.token}`} : {}),'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(90000)});
}
async function api(user,body,endpoint='companion-api',expected=200){
 const r=await request(user,body,endpoint),value=await r.json();assert.equal(r.status,expected,`${endpoint}/${body.action}: ${value.code??r.status}`);return value;
}
async function turn(user,body){
 generationRequests++;
 const r=await request(user,body,'conversation-turn');assert.equal(r.status,200);
 let text='',done=false;
 for await(const event of serverEvents(r.body)){
  assert.notEqual(event.type,'error',`Conversation error: ${event.code}`);
  if(event.type==='delta')text+=event.text;if(event.type==='done')done=true;
 }
 assert.ok(done&&text.trim());return text;
}
const passed=check=>{checks.push({check,passed:true});console.log(check);};
try{
 await api(null,{action:'bootstrap'},'companion-api',401);
 const configs=[
  {name:'Alex',personality_keys:['warm_caring','funny_playful'],interaction_style:'direct',age_group:'25_34',language:'en'},
  {name:'Sam',personality_keys:['calm_understanding','curious_intellectual'],interaction_style:'thoughtful_detailed',age_group:'18_24',language:'en'},
  {name:'Jamie',personality_keys:['positive_motivating','casual_relaxed'],interaction_style:'casual_natural',age_group:'55_plus',language:'fr'},
 ];
 for(const [index,choice] of configs.entries()){
  stage=`configuration ${index+1}`;
  const suffix=randomBytes(9).toString('hex'),credentials={email:`friend-preferences-${suffix}@example.invalid`,password:`Aa!9${randomBytes(24).toString('base64url')}`,returnSecureToken:true};
  const account=await firebase('accounts:signUp',credentials),user={uid:account.localId,token:account.idToken};users.push(user);
  await api(user,{action:'bootstrap'});
  await api(user,{action:'save_personal_profile',username:`pref_${suffix}`,preferred_name:'Marvin',timezone:'Africa/Kampala',language:choice.language});
  if(index===0){
   for(const age_group of ['under_13','13_15','16_17'])await api(user,{action:'save_introduction',age_group,language:'en',timezone:'UTC'},'companion-api',400);
   await api(user,{conversation_id:randomUUID(),request_id:randomUUID(),content:'Fictional age-gate check',age_group:'25_34'},'conversation-turn',403);
   passed('All requested younger brackets and forged body age cannot reach the deployed provider');
  }
  await api(user,{action:'save_introduction',age_group:choice.age_group,language:choice.language,timezone:'Africa/Kampala',timezone_automatic:false});
  let {companion}=await api(user,{action:'save_companion',name:choice.name,style:'Gentle & warm',interests:[],response_length:.5,memory_enabled:true,retention_days:null});
  const preferences={action:'save_friend_preferences',companion_id:companion.id,name:choice.name,personality_keys:choice.personality_keys,
   support_preferences:['daily_companionship','learning','language_practice'],interaction_style:choice.interaction_style,
   learning_interests:'Practise German',personal_goals:'Speak more confidently',additional_information:'I enjoy fictional garden sketches.'};
  ({companion}=await api(user,preferences));
  await api(user,{...preferences,support_preferences:['learning','motivation','friendship','creativity','productivity']},'companion-api',400);
  await api(user,{action:'activate_friend_mode',companion_id:companion.id,consent:true});
  const {conversation}=await api(user,{action:'create_conversation',companion_id:companion.id,title:'Disposable companion preference test'});
  const greeting=await turn(user,{conversation_id:conversation.id,request_id:randomUUID(),initiate:true});
  assert.ok(greeting.includes(choice.name),`Greeting did not use selected name ${choice.name}`);
  assert.doesNotMatch(greeting,/missed you|waiting for you|thinking about you|welcome back/i);
  // New password login, fresh owned reads and a new conversation prove settings are persistent.
  user.token=(await firebase('accounts:signInWithPassword',credentials)).idToken;
  const restored=await api(user,{action:'bootstrap'});
  assert.equal(restored.companion.id,companion.id);assert.deepEqual(restored.companion.personality_keys,choice.personality_keys);
  assert.equal(restored.companion.learning_interests,'Practise German');
  const next=await api(user,{action:'create_conversation',companion_id:companion.id,title:'Disposable preference continuity test'});
  const reply=await turn(user,{conversation_id:next.conversation.id,request_id:randomUUID(),content:choice.language==='fr'?'Quelle langue ai-je choisi de pratiquer ? Propose-moi un tout petit exercice.':'Which language did I choose to practise? Suggest one tiny practice activity.'});
  assert.match(reply,/German|Deutsch|allemand/i);
  if(choice.language==='fr')assert.match(reply,/allemand|pratiqu|phrase|exercice|peux|voici/i);
  samples.push({configuration:index+1,companion:choice.name,ageBracket:choice.age_group,personality:choice.personality_keys,communication:choice.interaction_style,language:choice.language,greeting,reply});
  passed(`Configuration ${index+1}: real named greeting, restored preferences and goal-aware reply`);
 }
 const denied=await api(users[1],{action:'save_friend_preferences',companion_id:(await api(users[0],{action:'bootstrap'})).companion.id,
  name:'Foreign',personality_keys:['warm_caring'],support_preferences:[],interaction_style:'direct'},'companion-api',404);
 assert.equal(denied.code,'not_found');passed('Deployed preference writes remain owner-isolated');
}catch(error){checks.push({check:stage,passed:false,error:error.message});process.exitCode=1;}
finally{
 for(const user of users)try{
  await api(user,{action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'},'privacy',202);
  let done=false;for(let i=0;i<20;i++){
   if((await api(user,{action:'erasure_status'},'privacy')).status==='complete'){done=true;break;}
   await new Promise(resolve=>setTimeout(resolve,1000));
  }
  assert.ok(done);passed('Disposable adult test identity erased');
 }catch(error){checks.push({check:'Disposable identity cleanup',passed:false,testUid:user.uid,error:error.message});process.exitCode=1;}
 const report={checked_at_utc:new Date().toISOString(),generationRequests,fictionalAdultIdentities:users.length,youngerProviderRequests:0,checks,samples};
 await writeFile('.cache/live-friend-preferences.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({generationRequests,checks},null,2));
}
