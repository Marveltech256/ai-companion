// Creates only an app-owned, Gemini-restricted server key. No plaintext output.
const path=require('node:path');
const fs=require('node:fs/promises');
const {execFileSync}=require('node:child_process');
const cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js'));
const {requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js'));
const {logger}=require(path.join(cli,'logger.js'));
logger.level='error';for(const transport of logger.transports??[])transport.level='error';
const project='ai-personal-companion',number='700569985311',ref='rvokidwyzwygpzzkpqck';
const keyId='ai-companion-gemini-server',displayName='Ai Companion Gemini Server';
const resource=`projects/${number}/locations/global/keys/${keyId}`;
const restrictedService='generativelanguage.googleapis.com';
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let stage='initialize';
(async()=>{
 const account=getGlobalDefaultAccount();
 await requireAuth({project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})});
 const usage=new Client({urlPrefix:'https://serviceusage.googleapis.com',apiVersion:'v1',auth:true});
 const keys=new Client({urlPrefix:'https://apikeys.googleapis.com',apiVersion:'v2',auth:true});
 const supabase=process.env.AI_COMPANION_SUPABASE_CLI;
 if(!supabase||!path.isAbsolute(supabase))throw new Error('Missing installed Supabase CLI.');
 const metadata=JSON.parse(execFileSync(supabase,['secrets','list',`--remote=${ref}`,'--output','json'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
 if(metadata.some(s=>s.name==='GEMINI_API_KEY'))throw new Error('Existing Gemini credential needs review before replacement.');
 async function operation(api,initial){
  let value=initial;const until=Date.now()+150000;
  while(!value.done){
   if(Date.now()>until)throw new Error('Google operation did not finish within the limit.');
   await pause(2000);
   value=(await api.get(`/${value.name}`,{skipLog:{resBody:true}})).body;
  }
  if(value.error)throw Object.assign(new Error('Google operation failed.'),{status:value.error.code});
  return value.response;
 }
 for(const service of ['apikeys.googleapis.com',restrictedService]){
  stage=`enable:${service}`;
  const status=(await usage.get(`/projects/${number}/services/${service}`)).body;
  if(status.state!=='ENABLED'){
   console.log(JSON.stringify({stage,state:'enabling'}));
   await operation(usage,(await usage.post(`/projects/${number}/services/${service}:enable`,{})).body);
  }
  console.log(JSON.stringify({service,state:'ENABLED'}));
 }
 let created=false,uploaded=false,temporary,secretFile;
 try{
  stage='restricted-key';let key;
  try{key=(await keys.get(`/${resource}`,{skipLog:{resBody:true}})).body;}
  catch(error){if(error.status!==404)throw error;}
  if(!key){
   key=await operation(keys,(await keys.post(`/projects/${number}/locations/global/keys`,{
    displayName,restrictions:{apiTargets:[{service:restrictedService}]},
   },{queryParams:{keyId},skipLog:{reqBody:true,resBody:true}})).body);created=true;
  }
  if(key.name!==resource||key.displayName!==displayName||key.deleteTime||key.serviceAccountEmail||
   key.restrictions?.apiTargets?.length!==1||key.restrictions.apiTargets[0].service!==restrictedService)
   throw new Error('Existing key does not match the dedicated Gemini restriction.');
  const keyString=(await keys.get(`/${resource}/keyString`,{skipLog:{resBody:true}})).body.keyString;
  if(typeof keyString!=='string'||!keyString)throw new Error('Google returned no key string.');
  console.log(JSON.stringify({stage:'restricted-key',resource,restrictedService,created}));
  stage='model-catalog';const catalog=[];let pageToken,modelStatus=200;
  do{
   const url=new URL('https://generativelanguage.googleapis.com/v1beta/models');
   url.searchParams.set('pageSize','1000');if(pageToken)url.searchParams.set('pageToken',pageToken);
   const response=await fetch(url,{headers:{'x-goog-api-key':keyString},signal:AbortSignal.timeout(20000)});
   const body=await response.json();
   if(!response.ok){modelStatus=response.status;break;}
   catalog.push(...(body.models??[]));pageToken=body.nextPageToken;
   if(catalog.length>3000)throw new Error('Unexpected model catalog size.');
  }while(pageToken);
  const usable=catalog.filter(m=>m.supportedGenerationMethods?.includes('generateContent'));
  const requested=process.env.GEMINI_SERVER_MODEL;
  const preferred=requested?[requested]:['gemini-3.5-flash-lite'];
  const selected=preferred.find(id=>usable.some(m=>m.name===`models/${id}`));
  if(requested&&!selected)throw new Error('Requested Gemini model is not available.');
  const values={GEMINI_API_KEY:keyString,GEMINI_BACKUP_ENABLED:'true'};
  if(selected){values.GEMINI_MODEL=selected;values.GEMINI_MEMORY_MODEL=selected;}
  stage='supabase-secret-upload';
  temporary=await fs.mkdtemp(path.join(process.cwd(),'.cache/gemini-server-config-'));
  const principal=execFileSync('whoami.exe',[],{encoding:'utf8'}).trim();
  execFileSync('icacls.exe',[temporary,'/inheritance:r','/grant:r',`${principal}:(OI)(CI)F`],{stdio:'pipe'});
  for(const value of Object.values(values))if(/[\r\n']/.test(value))throw new Error('Unexpected secret format.');
  secretFile=path.join(temporary,'server.env');
  await fs.writeFile(secretFile,Object.entries(values).map(([name,value])=>`${name}='${value}'`).join('\n')+'\n',{mode:0o600});
  execFileSync(supabase,['secrets','set',`--remote=${ref}`,'--env-file',secretFile,'--yes'],{stdio:['ignore','pipe','pipe']});
  uploaded=true;await fs.unlink(secretFile);secretFile=undefined;await fs.rmdir(temporary);temporary=undefined;
  const report={checked_at_utc:new Date().toISOString(),project,supabase_project:ref,key_resource:resource,
   restricted_api:restrictedService,new_key_created:created,model_catalog_status:modelStatus,
   selected_model:selected??null,uploaded_names:Object.keys(values),private_local_file_removed:true,billing_changed:false};
  await fs.writeFile(path.join(process.cwd(),'.cache/gemini-server-provisioning.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
 }finally{
  if(created&&!uploaded)await keys.delete(`/${resource}`,{skipLog:{resBody:true}}).catch(()=>console.error('New unused Gemini key could not be rolled back.'));
  if(secretFile)await fs.unlink(secretFile).catch(()=>console.error('Temporary server env file needs removal.'));
  if(temporary)await fs.rmdir(temporary).catch(()=>{});
 }
})().catch(error=>{console.error(JSON.stringify({stage,error:'Gemini provisioning did not complete.',status:error.status??null}));process.exitCode=1;});
