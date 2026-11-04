// Provision only the server identity needed by this app. Never logs key material.
const path=require('node:path');
const fs=require('node:fs/promises');
const {execFileSync}=require('node:child_process');
const cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js'));
const {requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js'));
const {logger}=require(path.join(cli,'logger.js'));
logger.level='error';for(const transport of logger.transports??[])transport.level='error';
const project='ai-personal-companion';const ref='rvokidwyzwygpzzkpqck';
const id='ai-companion-edge';const email=`${id}@${project}.iam.gserviceaccount.com`;
const roleId='aiCompanionEdge';const roleName=`projects/${project}/roles/${roleId}`;
const includedPermissions=['firebaseauth.users.get','firebaseauth.users.delete','cloudmessaging.messages.create'].sort();
let stage='initialize';
(async()=>{
 const account=getGlobalDefaultAccount();
 await requireAuth({project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})});
 const iam=new Client({urlPrefix:'https://iam.googleapis.com',apiVersion:'v1',auth:true});
 const crm=new Client({urlPrefix:'https://cloudresourcemanager.googleapis.com',apiVersion:'v1',auth:true});
 const requested=['iam.serviceAccounts.create','iam.serviceAccounts.get','iam.serviceAccountKeys.create','iam.serviceAccountKeys.delete',
  'iam.roles.create','iam.roles.get','resourcemanager.projects.getIamPolicy','resourcemanager.projects.setIamPolicy'];
 stage='permission-preflight';
 const tested=await crm.post(`/projects/${project}:testIamPermissions`,{permissions:requested});
 const missing=requested.filter(p=>!tested.body.permissions?.includes(p));
 console.log(JSON.stringify({stage,project,missingPermissions:missing}));
 if(!process.argv.includes('--apply'))return;
 if(missing.length)throw new Error('Missing project provisioning permissions.');
 const supabase=process.env.AI_COMPANION_SUPABASE_CLI;
 if(!supabase||!path.isAbsolute(supabase))throw new Error('Supply the installed Supabase CLI executable path.');
 const metadata=JSON.parse(execFileSync(supabase,['secrets','list',`--remote=${ref}`,'--output','json'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
 const hasCredential=metadata.some(s=>s.name==='FIREBASE_SERVICE_ACCOUNT_JSON');
 let keyName;let temporary;let secretFile;let uploaded=false;
 try{
  const values={FIREBASE_PROJECT_ID:project,ALLOWED_ORIGINS:'http://localhost:52100,http://127.0.0.1:52100,https://ai-personal-companion.firebaseapp.com,https://ai-personal-companion.web.app'};
  if(!hasCredential){
   stage='server-role';
   let role;try{role=(await iam.get(`/${roleName}`)).body;}catch(error){if(error.status!==404)throw error;}
   if(role){if(role.deleted||JSON.stringify([...role.includedPermissions].sort())!==JSON.stringify(includedPermissions))throw new Error('Existing dedicated role needs review.');}
   else await iam.post(`/projects/${project}/roles`,{roleId,role:{title:'Ai Companion Edge',description:'Account status, user-requested erasure and FCM only.',stage:'GA',includedPermissions}});
   stage='server-account';
   let service;try{service=(await iam.get(`/projects/${project}/serviceAccounts/${email}`)).body;}catch(error){if(error.status!==404)throw error;}
   if(service){if(service.disabled||service.displayName!=='Ai Companion Edge')throw new Error('Existing service account needs review.');}
   else await iam.post(`/projects/${project}/serviceAccounts`,{accountId:id,serviceAccount:{displayName:'Ai Companion Edge',description:'Server identity for Ai Companion Supabase Edge account verification, user-requested erasure and FCM.'}});
   stage='role-binding';
   const policy=(await crm.post(`/projects/${project}:getIamPolicy`,{options:{requestedPolicyVersion:3}})).body;
   policy.bindings??=[];
   const member=`serviceAccount:${email}`;
   if(policy.bindings.some(b=>b.role!==roleName&&b.members?.includes(member)))throw new Error('Dedicated service account has unexpected project roles.');
   let binding=policy.bindings.find(b=>b.role===roleName&&!b.condition);
   if(!binding){binding={role:roleName,members:[]};policy.bindings.push(binding);}
   if(!binding.members.includes(member)){
    binding.members.push(member);
    await crm.post(`/projects/${project}:setIamPolicy`,{policy,updateMask:'bindings,etag,version'});
   }
   stage='server-key';
   const key=(await iam.post(`/projects/${project}/serviceAccounts/${email}/keys`,{privateKeyType:'TYPE_GOOGLE_CREDENTIALS_FILE',keyAlgorithm:'KEY_ALG_RSA_2048'},
    {skipLog:{reqBody:true,resBody:true}})).body;
   keyName=key.name;
   const credential=JSON.parse(Buffer.from(key.privateKeyData,'base64').toString('utf8'));
   if(credential.project_id!==project||credential.client_email!==email)throw new Error('Server identity mismatch.');
   values.FIREBASE_SERVICE_ACCOUNT_JSON=JSON.stringify(credential);
  }
  stage='secure-secret-upload';
  temporary=await fs.mkdtemp(path.join(process.cwd(),'.cache/server-config-'));
  const principal=execFileSync('whoami.exe',[],{encoding:'utf8'}).trim();
  execFileSync('icacls.exe',[temporary,'/inheritance:r','/grant:r',`${principal}:(OI)(CI)F`],{stdio:'pipe'});
  secretFile=path.join(temporary,'.env');
  for(const value of Object.values(values))if(value.includes("'"))throw new Error('Unexpected environment quoting.');
  await fs.writeFile(secretFile,Object.entries(values).map(([name,value])=>`${name}='${value}'`).join('\n')+'\n',{mode:0o600});
  execFileSync(supabase,['secrets','set',`--remote=${ref}`,'--env-file',secretFile,'--yes'],{stdio:['ignore','pipe','pipe']});
  uploaded=true;
  const report={checked_at_utc:new Date().toISOString(),project,supabase_project:ref,service_account:email,
   custom_role:roleName,permissions:includedPermissions,credentialAlreadyPresent:hasCredential,uploadedNames:Object.keys(values),privateLocalFileRemoved:true};
  await fs.unlink(secretFile);secretFile=undefined;await fs.rmdir(temporary);temporary=undefined;
  await fs.writeFile(path.join(process.cwd(),'.cache/firebase-backend-configuration.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
 }finally{
  if(keyName&&!uploaded)await iam.delete(`/${keyName}`,{skipLog:{resBody:true}}).catch(()=>console.error('New unused server key could not be rolled back.'));
  if(secretFile)await fs.unlink(secretFile).catch(()=>console.error('Remove the temporary server environment file.'));
  if(temporary)await fs.rmdir(temporary).catch(()=>{});
 }
})().catch(error=>{console.error(JSON.stringify({stage,error:'Backend configuration did not complete.',status:error.status??null}));process.exitCode=1;});
