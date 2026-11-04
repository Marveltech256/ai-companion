// Creates isolated temporary identities, verifies real Firebase login/JWTs, and
// removes only identities created by this run. Never logs credentials/tokens.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {verifyFirebase} from '../supabase/functions/_shared/auth.ts';
const config=JSON.parse(await readFile(new URL('../config/development.json',import.meta.url),'utf8'));
const endpoint='https://identitytoolkit.googleapis.com/v1/';
const created=[];const results=[];
async function call(action,input){
 const response=await fetch(`${endpoint}${action}?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input),signal:AbortSignal.timeout(20000)});
 const body=await response.json();
 if(!response.ok)throw new Error(body.error?.message??`Firebase request returned ${response.status}`);
 return body;
}
async function verify(token,uid){
 const identity=await verifyFirebase(new Request('https://local-smoke.test',{headers:{Authorization:`Bearer ${token}`}}),config.FIREBASE_PROJECT_ID);
 if(identity.uid!==uid)throw new Error('Verified identity mismatch');
 return identity;
}
try{
 try{
  const guest=await call('accounts:signUp',{returnSecureToken:true});
  created.push({uid:guest.localId,token:guest.idToken});
  throw new Error('Anonymous signup must be disabled.');
 }catch(error){
  if(!['ADMIN_ONLY_OPERATION','OPERATION_NOT_ALLOWED'].includes(error.message))throw error;
  results.push({check:'Anonymous account creation is disabled',passed:true});
 }
 const email=`ai-companion-smoke-${randomBytes(12).toString('hex')}@example.invalid`;
 const password=`A!9a${randomBytes(24).toString('base64url')}`;
 const registered=await call('accounts:signUp',{email,password,returnSecureToken:true});
 created.push({uid:registered.localId,token:registered.idToken});
 await verify(registered.idToken,registered.localId);
 const login=await call('accounts:signInWithPassword',{email,password,returnSecureToken:true});
 const signedIn=await verify(login.idToken,registered.localId);
 results.push({check:'Email signup, password login and same-UID JWT verification',passed:signedIn.anonymous===false});
}catch(e){results.push({check:'Live Firebase authentication',passed:false,error:e.message});process.exitCode=1;}
finally{
 for(const record of created){
  try{await call('accounts:delete',{idToken:record.token});results.push({check:'Temporary test identity removed',passed:true});}
  catch(e){results.push({check:'Temporary test identity removal',passed:false,test_uid:record.uid,error:e.message});process.exitCode=1;}
 }
 const report={checked_at_utc:new Date().toISOString(),project:config.FIREBASE_PROJECT_ID,temporary_identities_created:created.length,results};
 await mkdir(new URL('../.cache/',import.meta.url),{recursive:true});
 await writeFile(new URL('../.cache/firebase-live-auth-test.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
}
