// Creates at most one isolated Firebase guest and never writes app data.
// Default: verify guest creation is disabled. --existing-guest checks handlers
// before the provider is disabled; only this script's own guest is deleted.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
const config=JSON.parse(await readFile(new URL('../config/development.json',import.meta.url),'utf8'));
const results=[];let guest;
const firebase=async(action,body)=>{
 const response=await fetch(`https://identitytoolkit.googleapis.com/v1/${action}?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 return {response,body:await response.json()};
};
try{
 const signup=await firebase('accounts:signUp',{returnSecureToken:true});
 if(signup.response.ok){
  guest=signup.body;
  assert.ok(process.argv.includes('--existing-guest'),'Anonymous signup must be disabled.');
  for(const name of ['companion-api','conversation-turn','voice','privacy']){
   const response=await fetch(`${config.SUPABASE_URL}/functions/v1/${name}`,{method:'POST',
    headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${guest.idToken}`,'Content-Type':'application/json'},
    body:JSON.stringify({action:'bootstrap'}),signal:AbortSignal.timeout(20000)});
   const body=await response.json();assert.equal(response.status,401);assert.equal(body.code,'sign_in_required');
   results.push({check:`${name} rejects a real Firebase guest token`,passed:true});
  }
 }else{
  assert.ok(!process.argv.includes('--existing-guest'),'Existing-guest check must run before provider shutdown.');
  assert.equal(signup.response.status,400);
  assert.ok(['ADMIN_ONLY_OPERATION','OPERATION_NOT_ALLOWED'].includes(signup.body.error?.message));
  results.push({check:'Firebase blocks anonymous account creation',passed:true});
 }
}catch(error){results.push({check:'Required sign-in',passed:false,error:error.message});process.exitCode=1;}
finally{
 if(guest){
  const deleted=await firebase('accounts:delete',{idToken:guest.idToken});
  results.push({check:'Only the temporary guest identity was removed',passed:deleted.response.ok});
  if(!deleted.response.ok)process.exitCode=1;
 }
 const report={checked_at_utc:new Date().toISOString(),results};
 await writeFile(new URL(`../.cache/${process.argv.includes('--existing-guest')?'existing-guest-denial':'anonymous-signup-disabled'}.json`,import.meta.url),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
}
