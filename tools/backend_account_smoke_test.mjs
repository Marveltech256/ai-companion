// Live, isolated account lifecycle check. Logs neither passwords nor tokens.
// Only identities created during this run may be erased.
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
const config=JSON.parse(await readFile(new URL('../config/development.json',import.meta.url),'utf8'));
const created=[];const results=[];let stage='begin';
const record=check=>{results.push({check,passed:true});console.log(check);};
async function firebase(action,body){
 const response=await fetch(`https://identitytoolkit.googleapis.com/v1/${action}?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const result=await response.json();
 if(!response.ok)throw new Error(`Firebase ${action} returned ${response.status}: ${result.error?.message?.split(' : ')[0]??'unknown'}`);
 return result;
}
async function edge(user,body,endpoint='companion-api',expected=200){
 const response=await fetch(`${config.SUPABASE_URL}/functions/v1/${endpoint}`,{
  method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${user.token}`,'Content-Type':'application/json',Origin:'http://localhost:52100'},
  body:JSON.stringify(body),signal:AbortSignal.timeout(25000)});
 const result=await response.json();
 if(response.status!==expected)throw new Error(`${endpoint}/${body.action}: HTTP ${response.status}, code ${result.code??'none'}`);
 assert.equal(response.headers.get('Access-Control-Allow-Origin'),'http://localhost:52100');
 return result;
}
async function create(){
 const suffix=randomBytes(10).toString('hex');const email=`ai-companion-live-${suffix}@example.invalid`;
 const password=`A!9a${randomBytes(24).toString('base64url')}`;
 const account=await firebase('accounts:signUp',{email,password,returnSecureToken:true});
 const user={uid:account.localId,token:account.idToken,email,password,username:`test_${suffix}`};
 created.push(user);return user;
}
try{
 stage='first signup and profile';const first=await create();
 let state=await edge(first,{action:'bootstrap'});assert.equal(state.profile.user_id,first.uid);
 const profile=await edge(first,{action:'save_personal_profile',username:first.username,preferred_name:'Marvin',display_name:null,timezone:'Africa/Kampala',language:null,general_location:null});
 assert.equal(profile.profile.preferred_name,'Marvin');assert.equal(profile.profile.username,first.username);
 record('Firebase signup -> Edge account check -> Supabase username/preferred-name save');
 await edge(first,{action:'save_introduction',age_group:'25_34',language:'en',timezone:'Africa/Kampala'});
 const saved=await edge(first,{action:'save_companion',name:'Lumi',style:'Gentle & warm',interests:[],memory_enabled:false,response_length:0.5,retention_days:null});
 assert.equal(saved.companion.owner_id,first.uid);
 const conversation=await edge(first,{action:'create_conversation',companion_id:saved.companion.id,title:'Isolated connection check'});
 assert.ok(conversation.conversation.id);
 stage='second identity and isolation';const second=await create();
 state=await edge(second,{action:'bootstrap',owner_id:first.uid});
 assert.equal(state.profile.user_id,second.uid);assert.equal(state.companion,null);
 const duplicate=await edge(second,{action:'save_personal_profile',username:first.username.toUpperCase(),preferred_name:'Second',display_name:null,timezone:'Africa/Kampala',language:null,general_location:null},'companion-api',409);
 assert.equal(duplicate.code,'username_taken');
 await edge(second,{action:'save_personal_profile',username:second.username,preferred_name:'Second',display_name:null,timezone:'Africa/Kampala',language:'en',general_location:null});
 await edge(second,{action:'save_introduction',age_group:'25_34',language:'en',timezone:'Africa/Kampala'});
 await edge(second,{action:'messages',conversation_id:conversation.conversation.id},'companion-api',404);
 record('Second account isolation and case-insensitive duplicate username rejection');
 stage='password login and restored profile';
 const login=await firebase('accounts:signInWithPassword',{email:first.email,password:first.password,returnSecureToken:true});
 assert.equal(login.localId,first.uid);first.token=login.idToken;
 state=await edge(first,{action:'bootstrap'});
 assert.equal(state.profile.preferred_name,'Marvin');assert.equal(state.profile.username,first.username);
 assert.equal(state.companion.id,saved.companion.id);
 record('Password login restores the same preferred name, username and companion');
}catch(error){results.push({check:stage,passed:false,error:error.message});process.exitCode=1;}
finally{
 for(const user of created){
  try{
   stage='temporary account cleanup';
   await edge(user,{action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'},'privacy',202);
   let complete=false;
   for(let attempt=0;attempt<20;attempt++){
    const status=await edge(user,{action:'erasure_status'},'privacy');
    if(status.status==='complete'){complete=true;break;}
    if(status.status==='failed')throw new Error('Server account erasure failed.');
    await new Promise(resolve=>setTimeout(resolve,1000));
   }
   assert.ok(complete,'Account erasure did not finish within the check window.');
   const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({idToken:user.token}),signal:AbortSignal.timeout(15000)});
   const body=await response.json();
   assert.ok(!response.ok&&['USER_NOT_FOUND','INVALID_ID_TOKEN'].includes(body.error?.message),'Firebase test identity still exists.');
   record('Temporary test profile/companion and Firebase identity erased through the deployed privacy API');
  }catch(error){results.push({check:'Temporary account cleanup',passed:false,test_uid:user.uid,error:error.message});process.exitCode=1;}
 }
 const report={checked_at_utc:new Date().toISOString(),firebase_project:config.FIREBASE_PROJECT_ID,supabase_project:'rvokidwyzwygpzzkpqck',
  temporary_identities_created:created.length,test_uids:created.map(u=>u.uid),results};
 await writeFile(new URL('../.cache/backend-live-account-test.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
}
