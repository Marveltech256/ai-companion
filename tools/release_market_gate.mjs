// Read-only provider gate; this is not a legal compliance certification or IP filter.
import {readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import path from 'node:path';

export function assessEuropeanAiSetup(report, now=Date.now()) {
 const checked=Date.parse(report?.checked_at_utc??'');
 if(report?.project!=='ai-personal-companion'||report?.read_only!==true||
    !Number.isFinite(checked)||checked>now+60000||now-checked>86400000)
  return {paidSetupVerified:false,reason:'provider_status_unverified'};
 if(!Array.isArray(report.checks))return {paidSetupVerified:false,reason:'provider_status_unverified'};
 const billing=report.checks.find(check=>check?.check==='billing-status');
 if(billing?.billingEnabled!==true)
  return {paidSetupVerified:false,reason:billing?.billingEnabled===false?'paid_api_setup_pending':'provider_status_unverified'};
 const service=report.checks.find(check=>check?.service==='generativelanguage.googleapis.com');
 if(service?.state!=='ENABLED')return {paidSetupVerified:false,reason:'gemini_service_unverified'};
 return {paidSetupVerified:true,reason:'paid_project_verified'};
}

async function main() {
 const args=process.argv.slice(2);
 if(args.some(arg=>!['--refresh','--european-ai-users'].includes(arg)))throw new Error('Unknown option.');
 if(args.includes('--refresh'))execFileSync(process.execPath,['tools/check_gemini_project.cjs'],{
  cwd:process.cwd(),windowsHide:true,stdio:['ignore','pipe','pipe'],timeout:45000,
 });
 const report=await readFile('.cache/gemini-project-preflight.json','utf8').then(JSON.parse).catch(()=>null);
 const state=assessEuropeanAiSetup(report);
 console.log(JSON.stringify({scope:'EEA, UK and Switzerland AI access',...state,
  checkedAt:report?.checked_at_utc??null,aiRequests:0,billingChanges:0,
  note:'Provider check only. Play distribution, service scope, payments and applicable law require separate review.'},null,2));
 if(args.includes('--european-ai-users')&&!state.paidSetupVerified)process.exitCode=2;
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href)
 main().catch(()=>{console.error('Provider readiness could not be verified. No billing or access settings were changed.');process.exitCode=1;});
