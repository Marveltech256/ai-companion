import {readFile,mkdir,writeFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url);
const config=JSON.parse(await readFile(new URL('config/development.json',root),'utf8'));
const headers={apikey:config.SUPABASE_PUBLISHABLE_KEY};
async function probe(name,url,options={},summarize=body=>({code:body.code??body.error?.message??null})){
 try{
  const response=await fetch(url,{...options,signal:AbortSignal.timeout(15000)});
  const body=await response.json().catch(()=>({}));
  return {name,status:response.status,...summarize(body)};
 }catch{return {name,status:null,error:'Connection could not be verified from this environment.'};}
}
const results=await Promise.all([
 probe('Supabase Auth health',`${config.SUPABASE_URL}/auth/v1/health`,{headers},body=>({service:body.name??null})),
 probe('Supabase profiles table (zero-row read)',`${config.SUPABASE_URL}/rest/v1/profiles?select=user_id&limit=0`,{headers},body=>({code:body.code??null,message:typeof body.message==='string'?body.message.slice(0,240):null})),
 ...['companion-api','conversation-turn','voice','privacy','checkin-dispatch','privacy-maintenance','billing','billing-notifications','review-access'].map(name=>
  probe(`Edge Function: ${name}`,`${config.SUPABASE_URL}/functions/v1/${name}`,{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({action:'bootstrap'})})),
 probe('Firebase public project configuration',`https://identitytoolkit.googleapis.com/v1/projects?key=${encodeURIComponent(config.FIREBASE_ANDROID_API_KEY)}`,{},body=>({
  projectId:body.projectId??null,projectNumber:body.projectNumber??null,passwordSignupAllowed:typeof body.allowPasswordUser==='boolean'?body.allowPasswordUser:null,
  providers:Array.isArray(body.idpConfig)?body.idpConfig.map(p=>({provider:p.providerId??p.provider??null,enabled:p.enabled??null})):[],
  authorizedDomains:Array.isArray(body.authorizedDomains)?body.authorizedDomains:[],error:body.error?.message??null,
 })),
 ...(config.GOOGLE_SERVER_CLIENT_ID?[probe('Firebase Google authorization start',
  `https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=${encodeURIComponent(config.FIREBASE_WEB_API_KEY)}`,
  {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({providerId:'google.com',continueUri:`https://${config.FIREBASE_AUTH_DOMAIN}/__/auth/handler`})},
  body=>{
   const uri=body.authUri?new URL(body.authUri):null;
   return {provider:body.providerId??null,authorizationHost:uri?.hostname??null,
    clientMatches:uri?.searchParams.get('client_id')===config.GOOGLE_SERVER_CLIENT_ID,
    callbackMatches:uri?.searchParams.get('redirect_uri')===`https://${config.FIREBASE_AUTH_DOMAIN}/__/auth/handler`,
    error:body.error?.message??null};
  })]:[]),
]);
const report={checked_at_utc:new Date().toISOString(),checked_at_kampala:new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Kampala',dateStyle:'long',timeStyle:'short'}).format(new Date()),read_only:true,results};
await mkdir(new URL('.cache/',root),{recursive:true});
await writeFile(new URL('.cache/backend-connection-check.json',root),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
