// Read-only preflight. Never retrieves an API-key string or changes billing.
const path=require('node:path');
const fs=require('node:fs/promises');
const cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js'));
const {requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js'));
const {logger}=require(path.join(cli,'logger.js'));
logger.level='error';for(const transport of logger.transports??[])transport.level='error';
(async()=>{
 const project='ai-personal-companion',number='700569985311';const account=getGlobalDefaultAccount();
 await requireAuth({project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})});
 const usage=new Client({urlPrefix:'https://serviceusage.googleapis.com',apiVersion:'v1',auth:true});
 const crm=new Client({urlPrefix:'https://cloudresourcemanager.googleapis.com',apiVersion:'v1',auth:true});
 const billing=new Client({urlPrefix:'https://cloudbilling.googleapis.com',apiVersion:'v1',auth:true});
 const keys=new Client({urlPrefix:'https://apikeys.googleapis.com',apiVersion:'v2',auth:true});
 const checks=[];
 for(const service of ['generativelanguage.googleapis.com','apikeys.googleapis.com']){
  try{const response=await usage.get(`/projects/${number}/services/${service}`);
   checks.push({service,state:response.body.state});}
  catch(error){checks.push({service,status:error.status??null});}
 }
 const permissions=['apikeys.keys.create','apikeys.keys.getKeyString','apikeys.keys.delete','serviceusage.services.enable'];
 const access=(await crm.post(`/projects/${project}:testIamPermissions`,{permissions})).body;
 checks.push({check:'restricted-key-provisioning',missingPermissions:permissions.filter(p=>!access.permissions?.includes(p))});
 try{const response=await billing.get(`/projects/${project}/billingInfo`);
  checks.push({check:'billing-status',billingEnabled:response.body.billingEnabled===true});}
 catch(error){checks.push({check:'billing-status',status:error.status??null});}
 try{
  const key=(await keys.get(`/projects/${number}/locations/global/keys/ai-companion-gemini-server`,{skipLog:{resBody:true}})).body;
  const targets=key.restrictions?.apiTargets??[];
  checks.push({check:'app-server-key',exists:!key.deleteTime,
   restrictedToGeminiOnly:targets.length===1&&targets[0].service==='generativelanguage.googleapis.com',
   displayName:key.displayName});
 }catch(error){checks.push({check:'app-server-key',status:error.status??null});}
 const report={checked_at_utc:new Date().toISOString(),project,read_only:true,checks};
 await fs.writeFile(path.join(process.cwd(),'.cache/gemini-project-preflight.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
})().catch(()=>{console.error('Gemini project preflight could not complete.');process.exitCode=1;});
