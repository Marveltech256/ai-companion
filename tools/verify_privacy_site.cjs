// Real HTTPS/browser verification with one disposable fictional identity.
// Never logs passwords/tokens; erases only the identity created in this process.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {spawn,spawnSync}=require('node:child_process');
const origin='https://ai-personal-companion-privacy.web.app';
const config=JSON.parse(fs.readFileSync('config/development.json','utf8'));
const profile=path.resolve('.cache',`privacy-site-chrome-${crypto.randomUUID()}`);
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let browser,ws,user,stage='public pages',deleted=false;const checks=[];
const passed=check=>{checks.push({check,passed:true});console.log(check);};
async function firebase(action,body,expected=200){
 const r=await fetch(`https://identitytoolkit.googleapis.com/v1/${action}?key=${encodeURIComponent(config.FIREBASE_WEB_API_KEY)}`,{
  method:'POST',headers:{'Content-Type':'application/json',Referer:origin+'/'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const result=await r.json();assert.equal(r.status,expected,`Firebase ${action}: HTTP ${r.status}`);return result;
}
async function edge(body,endpoint='privacy',expected=200,browserOrigin=origin){
 const r=await fetch(`${config.SUPABASE_URL}/functions/v1/${endpoint}`,{method:'POST',headers:{
  apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${user.token}`,'Content-Type':'application/json',Origin:browserOrigin},
  body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const value=await r.json();assert.equal(r.status,expected,`Application ${body.action}: HTTP ${r.status}`);
 assert.equal(r.headers.get('Access-Control-Allow-Origin'),browserOrigin);return value;
}
async function run(){
 for(const page of ['privacy.html','terms.html','delete-account.html']){
  const r=await fetch(`${origin}/${page}`,{signal:AbortSignal.timeout(20000)}),body=await r.text();
  assert.equal(r.status,200);assert.match(body,/Marvel tech solutions/);assert.match(body,/Uganda/);
  assert.doesNotMatch(body,/Operator name pending|Private preview|Country pending/);
  assert.equal(r.headers.get('X-Content-Type-Options'),'nosniff');assert.match(r.headers.get('Content-Security-Policy'),/frame-ancestors 'none'/);
 }
 passed('Published HTTPS pages show the supplied operator, support details and security headers');
 stage='browser sign-in module';
 browser=spawn('C:/Program Files/Google/Chrome/Application/chrome.exe',[
  '--headless=new','--no-first-run','--no-default-browser-check',`--user-data-dir=${profile}`,'--remote-debugging-port=0',`${origin}/delete-account.html`],
  {windowsHide:true,stdio:['ignore','ignore','pipe']});
 let devtools;browser.stderr.on('data',chunk=>{const match=String(chunk).match(/DevTools listening on (ws:\/\/[^\s]+)/);if(match)devtools=match[1];});
 const limit=Date.now()+30000;while(!devtools&&Date.now()<limit)await delay(100);assert.ok(devtools,'Headless browser did not start.');
 const port=new URL(devtools).port;let page;
 while(!page&&Date.now()<limit){const pages=await(await fetch(`http://127.0.0.1:${port}/json`)).json();page=pages.find(p=>p.url.startsWith(origin));if(!page)await delay(100);}
 assert.ok(page,'Owned browser page not found.');
 ws=new WebSocket(page.webSocketDebuggerUrl);await new Promise((ok,no)=>{ws.addEventListener('open',ok,{once:true});ws.addEventListener('error',no,{once:true});});
 let id=0;const replies=new Map();
 ws.addEventListener('message',event=>{const value=JSON.parse(event.data);if(value.id&&replies.has(value.id)){replies.get(value.id)(value);replies.delete(value.id);}});
 async function command(method,params={}){
  let timer;
  try{return await Promise.race([new Promise(resolve=>{const key=++id;replies.set(key,resolve);ws.send(JSON.stringify({id:key,method,params}));}),
   new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Owned browser operation timed out.')),25000);})]);}finally{clearTimeout(timer);}
 }
 async function evaluate(expression){const r=await command('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});
  if(r.error||r.result?.exceptionDetails)throw Error(user?'Browser page operation failed.':
   'Browser startup: '+(r.result?.exceptionDetails?.exception?.description??r.error?.message??'unknown').slice(0,700));return r.result?.result?.value;}
 await command('Page.enable');
 const readyUntil=Date.now()+20000;
 while(Date.now()<readyUntil){if(await evaluate(`location.origin===${JSON.stringify(origin)} && document.readyState==='complete'`))break;await delay(100);}
 await evaluate(`(async()=>{await import('/delete-account.mjs');await document.fonts.ready;return true;})()`);
 assert.equal(await evaluate(`document.getElementById('delete').disabled && document.getElementById('account').hidden`),true);
 await command('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 fs.mkdirSync('build/privacy-site-review',{recursive:true});
 const screenshot=await command('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
 fs.writeFileSync('build/privacy-site-review/delete-account-mobile.png',Buffer.from(screenshot.result.data,'base64'));
 assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'),true);
 passed('Real Chrome loads Firebase modules under the live CSP; mobile deletion form has no horizontal overflow');
 stage='fictional account creation';const suffix=crypto.randomBytes(10).toString('hex');
 const email=`privacy-hosting-${suffix}@example.invalid`,password=`Aa!9${crypto.randomBytes(24).toString('base64url')}`;
 const created=await firebase('accounts:signUp',{email,password,returnSecureToken:true});
 user={uid:created.localId,token:created.idToken};
 await edge({action:'bootstrap'},'companion-api'); // Has a profile, no introduction, companion or subscription.
 stage='real web email sign-in';
 await evaluate(`(()=>{document.getElementById('email').value=${JSON.stringify(email)};document.getElementById('password').value=${JSON.stringify(password)};document.getElementById('email-form').requestSubmit();return true;})()`);
 async function waitFor(expression,seconds=30){const until=Date.now()+seconds*1000;while(Date.now()<until){if(await evaluate(expression))return;await delay(200);}throw Error('Web flow did not finish in the check window.');}
 await waitFor(`!document.getElementById('account').hidden && !document.getElementById('sign-out').disabled`);
 assert.equal(await evaluate(`document.getElementById('delete').disabled && document.getElementById('password').value===''`),true);
 await evaluate(`(()=>{const input=document.getElementById('confirmation');input.value='DELETE';input.dispatchEvent(new Event('input'));return true;})()`);
 assert.equal(await evaluate(`document.getElementById('delete').disabled`),true);
 passed('Real Firebase email sign-in works from the new domain; incomplete confirmation cannot enable deletion');
 stage='real browser account erasure';
 await evaluate(`(()=>{const input=document.getElementById('confirmation');input.value='DELETE_MY_ACCOUNT';input.dispatchEvent(new Event('input'));document.getElementById('delete-form').requestSubmit();return true;})()`);
 await waitFor(`document.getElementById('status').textContent.includes('have been deleted')`,50);
 const status=await edge({action:'erasure_status'});assert.equal(status.status,'complete');
 const lookup=await firebase('accounts:lookup',{idToken:user.token},400);
 assert.ok(['USER_NOT_FOUND','INVALID_ID_TOKEN'].includes(lookup.error?.message));deleted=true;
 passed('Outside-app deletion works without onboarding or payment; Firebase identity and application erasure complete');
 const preflight=await fetch(`${config.SUPABASE_URL}/functions/v1/privacy`,{method:'OPTIONS',headers:{Origin:origin,'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization,apikey,content-type'}});
 assert.equal(preflight.status,204);assert.equal(preflight.headers.get('Access-Control-Allow-Origin'),origin);
 passed('New HTTPS origin passes API preflight with explicit origin matching');
}
(async()=>{
 try{await run();}catch(error){checks.push({check:stage,passed:false,error:error.message});process.exitCode=1;}
 finally{
  if(user&&!deleted){try{
   await edge({action:'request_account_erasure',confirmation:'DELETE_MY_ACCOUNT'},'privacy',202,'http://localhost:52100');
   for(let n=0;n<20;n++){if((await edge({action:'erasure_status'},'privacy',200,'http://localhost:52100')).status==='complete'){deleted=true;break;}await delay(1000);}
  }catch{checks.push({check:'Disposable account cleanup',passed:false,test_uid:user.uid});process.exitCode=1;}}
  ws?.close();if(browser?.pid)spawnSync('taskkill.exe',['/PID',String(browser.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
  if(path.dirname(profile)===path.resolve('.cache')&&path.basename(profile).startsWith('privacy-site-chrome-')){
   try{fs.rmSync(profile,{recursive:true,force:true,maxRetries:3,retryDelay:100});}catch{}
  }
  const report={checked_at_utc:new Date().toISOString(),origin,operator:'Marvel tech solutions',country:'Uganda',
   temporary_identities_created:user?1:0,temporary_identity_erased:deleted,ai_requests:0,purchases:0,checks};
  fs.writeFileSync('.cache/privacy-site-verification.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
 }
})();
