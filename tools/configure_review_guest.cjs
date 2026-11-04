// Owner-only provisioning. Never prints the plaintext review access code.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const cli=process.env.AI_COMPANION_SUPABASE_CLI,ref='rvokidwyzwygpzzkpqck';
const enable=process.argv.includes('--enable'),disable=process.argv.includes('--disable');
if(!cli||!path.isAbsolute(cli)||enable===disable)throw Error('Supply the Supabase CLI path and exactly one of --enable / --disable.');
const directory=path.resolve('.cache/review-guest-private'),instructions=path.resolve('config/PLAY_REVIEW_ACCESS.private.txt');
let stage='preflight';
function run(file,args){return execFileSync(file,args,{encoding:'utf8',windowsHide:true,timeout:60000,stdio:['ignore','pipe','pipe']});}
const principal=run('whoami.exe',[]).trim();
fs.mkdirSync(directory,{recursive:true});run('icacls.exe',[directory,'/inheritance:r','/grant:r',`${principal}:(OI)(CI)F`]);
const sqlFile=path.join(directory,'operation.sql'),envFile=path.join(directory,'.env');
const digest=s=>crypto.createHash('sha256').update(s).digest('hex');
function query(sql,readonly=false){fs.writeFileSync(sqlFile,sql);const out=run(cli,['db','query',`--remote=${ref}`,'--file',sqlFile,'--output','json',...(readonly?['--read-only']:['--yes'])]);return JSON.parse(out.slice(out.indexOf('{'))).rows;}
(async()=>{
 const config=JSON.parse(fs.readFileSync('config/development.json','utf8'));
 const metadata=JSON.parse(run(cli,['secrets','list',`--remote=${ref}`,'--output','json']));
 const before=query('select enabled,version from public.review_configuration where singleton;',true)[0];
 let values;
 if(enable){
  const status=await fetch(`${config.SUPABASE_URL}/functions/v1/review-access`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},body:'{"action":"status"}',signal:AbortSignal.timeout(20000)});
  if(status.status!==200)throw Error('Deploy review-access before activating it.');await status.body?.cancel();
  const existing=metadata.find(s=>s.name==='REVIEW_GUEST_CODE_HASH');
  let code;if(fs.existsSync(instructions))code=fs.readFileSync(instructions,'utf8').match(/^Access code: ([A-Za-z0-9_-]{43})$/m)?.[1];
  if(existing&&(!code||(existing.digest??existing.value)!==digest(digest(code))))throw Error('Existing review code differs; do not replace it automatically.');
  if(!code){
   code=crypto.randomBytes(32).toString('base64url');
   // Restrict the empty file before writing its private code.
   fs.closeSync(fs.openSync(instructions,'wx'));run('icacls.exe',[instructions,'/inheritance:r','/grant:r',`${principal}:F`]);
   fs.writeFileSync(instructions,`AI COMPANION — PRIVATE PLAY REVIEW ACCESS\nOperator: Marvel tech solutions, Uganda\n\nAccess code: ${code}\n\nPaste these instructions into Play Console > App content > App access:\n1. Open Ai Companion and tap "Guest for app review" on the welcome screen.\n2. Enter the access code above and tap "Continue as guest". No email, Google login or payment is needed for this route.\n3. Confirm the adult age range (18+), language and time zone, then complete the normal companion introduction/setup.\n4. Test the same Home, Chat, memory, recorded messages and text/voice replies available to signed-in users. Talk's real-time calling remains marked Coming Soon.\n5. Use fictional names and conversation details during the controlled test, while paid AI setup remains deferred.\n6. The current guest workspace restores on the same installation. "Exit guest" signs out; entering the code again creates a separate fresh workspace.\n7. Account deletion is available in Settings; confirm the review code again, then type DELETE_MY_ACCOUNT.\n\nThe code is reusable and has no automatic expiry while review access remains enabled. Anyone holding it can enter this protected route; the app does not identify Google reviewers automatically. Do not post the code publicly or put it in the store listing.\n\nAfter review, disable entry and revoke current guests with the owning Supabase CLI configured:\nnode tools/configure_review_guest.cjs --disable\nOr set public.review_configuration.enabled=false in trusted SQL. Guest rows/data are erased by the existing daily privacy worker when disabled, version-revoked or inactive for 30 days.\n`);
  }
  values={REVIEW_GUEST_ENABLED:'true',REVIEW_GUEST_CODE_HASH:digest(code)};
 }else{
  stage='revoke-guests';query('update public.review_configuration set enabled=false,version=gen_random_uuid() where singleton; select public.morrow_review_cleanup();');
  values={REVIEW_GUEST_ENABLED:'false'};
 }
 stage='upload-server-flags';fs.writeFileSync(envFile,Object.entries(values).map(([k,v])=>`${k}='${v}'`).join('\n')+'\n');
 run(cli,['secrets','set',`--remote=${ref}`,'--env-file',envFile,'--yes']);
 if(enable){stage='activate-guest-access';query('update public.review_configuration set enabled=true where singleton;');}
 const after=query('select enabled,version from public.review_configuration where singleton;',true)[0];
 if(after.enabled!==enable)throw Error('Review switch did not reach the requested state.');
 fs.unlinkSync(envFile);fs.unlinkSync(sqlFile);
 const report={checked_at_utc:new Date().toISOString(),review_access_enabled:after.enabled,version:after.version,
  instructions_file:'config/PLAY_REVIEW_ACCESS.private.txt',plaintext_code_logged:false,anonymous_firebase_changed:false,
  purchases_changed:false,existing_data_changed:false,old_versions_revoked:disable&&before.version!==after.version};
 fs.writeFileSync('.cache/review-guest-activation.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(JSON.stringify({stage,complete:false,reason:error.message?.startsWith('Existing review')?error.message:'Review provisioning stopped; credentials and command output suppressed.'}));process.exitCode=1;});
