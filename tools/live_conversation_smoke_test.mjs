// Real provider requests through the deployed app API, using one isolated user.
// Only that test identity/data is erased. Credentials/tokens are never logged.
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {serverEvents} from '../supabase/functions/_shared/openai.ts';
const config=JSON.parse(await readFile(new URL('../config/development.json',import.meta.url),'utf8'));
const results=[];let user,stage='signup',exampleReply,frenchReply;
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function firebase(action,body){
 const response=await fetch(`https://identitytoolkit.googleapis.com/v1/${action}?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const result=await response.json();if(!response.ok)throw new Error(`Firebase request failed (${response.status}).`);return result;
}
async function request(endpoint,body){
 return fetch(`${config.SUPABASE_URL}/functions/v1/${endpoint}`,{method:'POST',
  headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${user.token}`,'Content-Type':'application/json'},
  body:JSON.stringify(body),signal:AbortSignal.timeout(100000)});
}
async function api(body,endpoint='companion-api',expected=200){
 const response=await request(endpoint,body);const result=await response.json();
 if(response.status!==expected)throw new Error(`App API ${body.action}: HTTP ${response.status}, code ${result.code??'none'}.`);
 return result;
}
async function turn(body){
 const response=await request('conversation-turn',body);
 if(!response.ok)throw new Error(`Conversation HTTP ${response.status}.`);
 assert.ok(response.headers.get('Content-Type')?.includes('text/event-stream'));
 let output='',done=false;
 for await(const event of serverEvents(response.body)){
  if(event.type==='error')throw new Error(`Conversation error: ${event.code}.`);
  if(event.type==='delta')output+=event.text;
  if(event.type==='done')done=true;
 }
 assert.ok(done&&output.trim(),'Provider did not finish a real reply.');return output;
}
const passed=check=>{results.push({check,passed:true});console.log(check);};
try{
 const suffix=randomBytes(10).toString('hex');
 const credentials={email:`ai-conversation-${suffix}@example.invalid`,password:`Aa!9${randomBytes(24).toString('base64url')}`,returnSecureToken:true};
 const account=await firebase('accounts:signUp',credentials);
 user={uid:account.localId,token:account.idToken};
 await api({action:'bootstrap'});
 await api({action:'save_personal_profile',username:`ai_${suffix}`,preferred_name:'Marvin',display_name:null,timezone:'Africa/Kampala',language:null,general_location:null});
 const denied=await api({action:'save_companion',name:'Lumi',style:'Gentle & warm',interests:[],response_length:.2,memory_enabled:false,retention_days:null},'companion-api',403);
 assert.equal(denied.code,'introduction_required');
 await api({action:'save_introduction',age_group:'15_17',language:'en',timezone:'Africa/Kampala'},'companion-api',400);
 const introduction=await api({action:'save_introduction',age_group:'25_34',language:'en',timezone:'Africa/Kampala'});
 assert.equal(introduction.profile.age_group,'25_34');
 passed('Unconfirmed/under-18 introduction denied; explicit adult age, language and timezone saved');
 const saved=await api({action:'save_companion',name:'Lumi',style:'Gentle & warm',interests:['Art & making'],response_length:.2,memory_enabled:true,retention_days:null});
 await api({action:'activate_friend_mode',companion_id:saved.companion.id,consent:true});
 await api({action:'complete_welcome'});
 const created=await api({action:'create_conversation',companion_id:saved.companion.id,title:'Isolated live AI verification'});
 const conversation_id=created.conversation.id;
 stage='real assistant greeting';
 exampleReply=await turn({conversation_id,request_id:randomUUID(),initiate:true});
 assert.doesNotMatch(exampleReply,/welcome back|see you again|thinking about|waiting for you|missed you/i);
 const greeting=await api({action:'messages',conversation_id});
 assert.equal(greeting.messages.length,1);assert.equal(greeting.messages[0].role,'assistant');
 assert.equal(greeting.messages[0].content,exampleReply);
 passed('Real streamed assistant greeting persisted without a fabricated user message');
 stage='real typed reply and idempotent history';
 const message={conversation_id,request_id:randomUUID(),content:'I enjoy gardening as a hobby. Please respond with one short sentence.'};
 const reply=await turn(message);assert.ok(reply.trim());
 const replay=await turn(message);assert.equal(replay,reply);
 const history=await api({action:'messages',conversation_id});
 assert.equal(history.messages.length,3);assert.equal(history.messages.filter(m=>m.role==='user').length,1);
 assert.equal(history.messages.filter(m=>m.role==='assistant').length,2);
 passed('Real AI reply and identical retry preserve exactly one owned user/assistant turn');
 stage='live memory extraction';let found=false;
 for(let attempt=0;attempt<20;attempt++){
  const {memories}=await api({action:'list_memories',companion_id:saved.companion.id});
  if(memories.some(m=>/gardening/i.test(`${m.content} ${m.source_quote??''}`))){found=true;break;}
  await pause(2000);
 }
 assert.ok(found,'The provider reply succeeded, but a grounded gardening memory was not recovered within the check window.');
 passed('Real structured memory extraction saved the explicitly supplied gardening fact');
 stage='returning account and cross-conversation recall';
 const login=await firebase('accounts:signInWithPassword',credentials);assert.equal(login.localId,user.uid);user.token=login.idToken;
 const restored=await api({action:'bootstrap'});
 assert.equal(restored.profile.preferred_name,'Marvin');assert.equal(restored.profile.age_group,'25_34');
 assert.ok(restored.profile.welcome_completed_at);assert.equal(restored.companion.id,saved.companion.id);
 const next=await api({action:'create_conversation',companion_id:saved.companion.id,title:'Isolated continuity verification'});
 const recall=await turn({conversation_id:next.conversation.id,request_id:randomUUID(),content:'What hobby have I told you I enjoy? Reply with one short sentence.'});
 assert.match(recall,/gardening/i);
 passed('Fresh password login preserves the completed welcome and recalls the owned hobby in a new conversation');
 stage='selected language in a fresh conversation';
 await api({action:'save_introduction',age_group:'25_34',language:'fr',timezone:'Africa/Kampala'});
 const french=await api({action:'create_conversation',companion_id:saved.companion.id,title:'Isolated language verification'});
 frenchReply=await turn({conversation_id:french.conversation.id,request_id:randomUUID(),initiate:true});
 assert.match(frenchReply,/bonjour|salut|bonsoir|plaisir|heureux|rav[iie]|journée|revoir|comment|jardin|content/i);
 passed('A fresh conversation greets the returning user in the selected French language');
 const home=await api({action:'home_summary',companion_id:saved.companion.id});
 assert.equal(home.clock.timezone,'Africa/Kampala');assert.ok(home.last_user_message_at);
 assert.equal(home.reminders.length,0);assert.equal(home.events.length,0);
 passed('Home uses the actual profile timezone and conversation activity without invented reminders/events');
}catch(error){results.push({check:stage,passed:false,error:error.message});process.exitCode=1;}
finally{
 if(user){
  try{
   await api({action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'},'privacy',202);
   let complete=false;
   for(let attempt=0;attempt<20;attempt++){
    const status=await api({action:'erasure_status'},'privacy');
    if(status.status==='complete'){complete=true;break;}
    if(status.status==='failed')throw new Error('Test account erasure failed.');
    await pause(1000);
   }
   assert.ok(complete,'Test account erasure did not finish.');
   passed('Isolated test account and its conversations/memories erased through the deployed privacy API');
  }catch(error){results.push({check:'Test cleanup',passed:false,test_uid:user.uid,error:error.message});process.exitCode=1;}
 }
 const report={checked_at_utc:new Date().toISOString(),supabase_project:'rvokidwyzwygpzzkpqck',temporary_test_uid:user?.uid,
  synthetic_test_greeting:exampleReply,synthetic_french_greeting:frenchReply,results};
 await writeFile(new URL('../.cache/live-conversation-verification.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
}
