// Minimal provider check with bounded retries. Reports status, never keys.
const path=require('node:path');
const fs=require('node:fs/promises');
const cli=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount}=require(path.join(cli,'auth.js'));
const {requireAuth}=require(path.join(cli,'requireAuth.js'));
const {Client}=require(path.join(cli,'apiv2.js'));
const {logger}=require(path.join(cli,'logger.js'));
logger.level='error';for(const transport of logger.transports??[])transport.level='error';
(async()=>{
 const project='ai-personal-companion';const account=getGlobalDefaultAccount();
 await requireAuth({project,projectId:project,nonInteractive:true,...(account?{user:account.user,tokens:account.tokens}:{})});
 const provisioning=JSON.parse(await fs.readFile(path.join(process.cwd(),'.cache/gemini-server-provisioning.json'),'utf8'));
 const api=new Client({urlPrefix:'https://apikeys.googleapis.com',apiVersion:'v2',auth:true});
 const key=(await api.get(`/${provisioning.key_resource}/keyString`,{skipLog:{resBody:true}})).body.keyString;
 const model=process.env.GEMINI_DIAGNOSTIC_MODEL||provisioning.selected_model;
 if(!/^[a-zA-Z0-9._-]+$/.test(model))throw new Error('Missing model.');
 const catalogResponse=await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000',{
  headers:{'x-goog-api-key':key},signal:AbortSignal.timeout(20000)});
 const catalog=await catalogResponse.json();
 const flashModels=(catalog.models??[]).filter(m=>/flash/.test(m.name)&&m.supportedGenerationMethods?.includes('generateContent')).map(m=>m.name.replace(/^models\//,''));
 if(!flashModels.includes(model))throw new Error('Model was not found in the current catalog.');
 let response,body;
 for(let attempt=0;attempt<3;attempt++){
 response=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,{
  method:'POST',headers:{'x-goog-api-key':key,'Content-Type':'application/json'},
  body:JSON.stringify({contents:[{role:'user',parts:[{text:'Reply only with OK.'}]}],generationConfig:{maxOutputTokens:1024,
   ...(model.startsWith('gemini-2.5-flash')?{thinkingConfig:{thinkingBudget:0}}:{})}}),
  signal:AbortSignal.timeout(30000)});
 body=await response.json();
 if(![429,503].includes(response.status)||attempt===2)break;
 const seconds=Number(response.headers.get('retry-after'))||Number.parseFloat((body.error?.details??[]).find(d=>d.retryDelay)?.retryDelay??'')||2**(attempt+1);
 await new Promise(resolve=>setTimeout(resolve,Math.min(15000,seconds*1000)));
 }
 const report={checked_at_utc:new Date().toISOString(),project,model,http_status:response.status,
  error_status:body.error?.status??null,
  error_message:typeof body.error?.message==='string'?body.error.message.replaceAll(key,'[redacted]').slice(0,500):null,
  supported_flash_models:flashModels,
  reasons:(body.error?.details??[]).flatMap(detail=>detail.reason?[detail.reason]:[]),
  quota_violations:(body.error?.details??[]).flatMap(detail=>(detail.violations??[]).map(value=>({
   quotaMetric:value.quotaMetric,quotaId:value.quotaId,quotaValue:value.quotaValue,quotaDimensions:value.quotaDimensions}))),
  retry_delay:(body.error?.details??[]).find(detail=>detail.retryDelay)?.retryDelay??null,
  finish_reason:body.candidates?.[0]?.finishReason??null,
  generated_text_present:body.candidates?.some(c=>c.content?.parts?.some(p=>typeof p.text==='string'&&!p.thought))??false};
 await fs.writeFile(path.join(process.cwd(),'.cache/gemini-live-provider-access.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
 if(!response.ok||!report.generated_text_present||report.finish_reason!=='STOP')process.exitCode=1;
})().catch(()=>{console.error('Gemini access diagnostic could not complete.');process.exitCode=1;});
