// Securely provision operations secrets. Activate cleanup, never AI check-ins.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const root=process.cwd(),cli=process.env.AI_COMPANION_SUPABASE_CLI,ref='rvokidwyzwygpzzkpqck';
if(!cli||!path.isAbsolute(cli))throw Error('Supply AI_COMPANION_SUPABASE_CLI.');
let stage='preflight';
function run(binary,args){const r=spawnSync(binary,args,{encoding:'utf8',windowsHide:true,maxBuffer:4194304});
 if(r.error||r.status!==0)throw Error(`Operations command failed during ${stage}; secret output suppressed.`);return r.stdout;}
const parse=text=>JSON.parse(text.slice(text.indexOf('{')));
const directory=path.join(root,'.cache/operations-private');fs.mkdirSync(directory,{recursive:true});
const principal=run('whoami.exe',[]).trim();run('icacls.exe',[directory,'/inheritance:r','/grant:r',`${principal}:(OI)(CI)F`]);
const envPath=path.join(directory,'.env'),sqlPath=path.join(directory,'operation.sql');
function query(sql,readonly=false){fs.writeFileSync(sqlPath,sql);const text=run(cli,['db','query',`--remote=${ref}`,'--file',sqlPath,'--output','json',...(readonly?['--read-only']:['--yes'])]);return parse(text).rows;}
(async()=>{
 const raw=run(cli,['secrets','list',`--remote=${ref}`,'--output','json']);
 const metadata=JSON.parse(raw),names=new Set(metadata.map(s=>s.name));
 const preflight=query("select exists(select 1 from vault.secrets where name='ai_companion_scheduler_secret') as vault_secret",true)[0];
 let values={};
 if(fs.existsSync(envPath))for(const line of fs.readFileSync(envPath,'utf8').trim().split('\n')){const m=line.match(/^(\w+)='([A-Za-z0-9_-]+)'$/);if(m)values[m[1]]=m[2];}
 if(names.has('SCHEDULER_SECRET')||preflight.vault_secret){
  if(!values.SCHEDULER_SECRET)throw Error('Existing scheduler configuration found. Do not rotate or overwrite it automatically.');
  const stored=metadata.find(s=>s.name==='SCHEDULER_SECRET');
  if(stored?.digest&&stored.digest!==crypto.createHash('sha256').update(values.SCHEDULER_SECRET).digest('hex'))throw Error('Local recovery secret does not match the existing Edge digest.');
 }else values.SCHEDULER_SECRET=crypto.randomBytes(48).toString('base64url');
 if(!names.has('BILLING_TOKEN_ENCRYPTION_KEY')&&!values.BILLING_TOKEN_ENCRYPTION_KEY)values.BILLING_TOKEN_ENCRYPTION_KEY=crypto.randomBytes(32).toString('base64url');
 if(!names.has('BILLING_FEATURE_ENABLED'))values.BILLING_FEATURE_ENABLED='false';
 fs.writeFileSync(envPath,Object.entries(values).map(([k,v])=>`${k}='${v}'`).join('\n')+'\n');
 stage='upload-private-secrets';run(cli,['secrets','set',`--remote=${ref}`,'--env-file',envPath,'--yes']);
 stage='prepare-extensions';query('create extension if not exists pg_cron with schema pg_catalog; create extension if not exists pg_net with schema extensions;');
 stage='vault-provision';if(!preflight.vault_secret)query(`select vault.create_secret('${values.SCHEDULER_SECRET}','ai_companion_scheduler_secret','Ai Companion authenticated background maintenance');`);
 stage='prepare-inactive-jobs';
 const jobs=query("select jobname,active from cron.job where jobname in ('ai-companion-checkins','ai-companion-privacy')",true);
 if(jobs.length===0)query(fs.readFileSync('supabase/setup/prepare_schedulers.sql','utf8'));
 else if(jobs.length!==2)throw Error('Partial scheduler jobs found; inspect before changing them.');
 stage='verify-maintenance';
 const response=await fetch(`https://${ref}.supabase.co/functions/v1/privacy-maintenance`,{method:'POST',headers:{Authorization:`Bearer ${values.SCHEDULER_SECRET}`,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(90000)});
 if(!response.ok)throw Error(`Maintenance check returned HTTP ${response.status}; jobs remain unactivated.`);
 await response.body?.cancel();
 stage='activate-privacy-only';query("select cron.alter_job(jobid,active:=true) from cron.job where jobname='ai-companion-privacy';");
 const state=query("select jobname,schedule,active from cron.job where jobname in ('ai-companion-checkins','ai-companion-privacy') order by jobname",true);
 if(state.find(j=>j.jobname==='ai-companion-checkins')?.active)throw Error('Unexpected active AI check-in job; inspect its earlier activation.');
 fs.unlinkSync(envPath);fs.unlinkSync(sqlPath);
 const report={checked_at_utc:new Date().toISOString(),maintenance_http_status:response.status,jobs:state,
  billing_feature_enabled:false,additional_ai_generation_enabled:false,private_upload_files_removed:true};
 fs.writeFileSync('.cache/operations-activation.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(JSON.stringify({stage,completed:false,error:error.message}));process.exitCode=1;});
