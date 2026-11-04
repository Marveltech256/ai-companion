// Test only our isolated compiled probe in a fresh headless Chrome profile.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto');
const {spawn,spawnSync}=require('node:child_process');
const root=path.resolve('.cache/browser-storage-probe'),profile=path.resolve('.cache',`browser-storage-chrome-${crypto.randomUUID()}`);
const chrome='C:/Program Files/Google/Chrome/Application/chrome.exe';
const types={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm','.json':'application/json','.ttf':'font/ttf'};
let child,ws,server;const deadline=Date.now()+60000;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function run(){
 if(!fs.existsSync(path.join(root,'index.html')))throw Error('Build the isolated browser storage probe first.');
 server=http.createServer((req,res)=>{
  try{const route=decodeURIComponent(new URL(req.url,'http://localhost').pathname),file=path.resolve(root,`.${route==='/'?'/index.html':route}`);
   if(!file.startsWith(root+path.sep)||!fs.statSync(file).isFile()){res.writeHead(404);return res.end();}
   res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});fs.createReadStream(file).pipe(res);
  }catch{res.writeHead(404);res.end();}
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
 child=spawn(chrome,['--headless=new','--no-first-run','--no-default-browser-check',`--user-data-dir=${profile}`,'--remote-debugging-port=0',origin],
  {windowsHide:true,stdio:['ignore','ignore','pipe']});
 let devtools;
 child.stderr.on('data',chunk=>{const match=String(chunk).match(/DevTools listening on (ws:\/\/[^\s]+)/);if(match)devtools=match[1];});
 while(!devtools&&Date.now()<deadline)await delay(100);
 if(!devtools)throw Error('Owned headless Chrome did not start.');
 const port=new URL(devtools).port;let page;
 while(!page&&Date.now()<deadline){const pages=await(await fetch(`http://127.0.0.1:${port}/json`)).json();page=pages.find(p=>p.url.startsWith(origin));if(!page)await delay(100);}
 if(!page)throw Error('Owned probe page unavailable.');
 ws=new WebSocket(page.webSocketDebuggerUrl);await new Promise((ok,no)=>{ws.addEventListener('open',ok,{once:true});ws.addEventListener('error',no,{once:true});});
 let id=0;const requests=new Map();
 ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id&&requests.has(m.id)){requests.get(m.id)(m);requests.delete(m.id);}});
 function command(method,params){return Promise.race([new Promise(resolve=>{const key=++id;requests.set(key,resolve);ws.send(JSON.stringify({id:key,method,params}));}),delay(3000).then(()=>{throw Error('Probe debugger timeout.');})]);}
 while(Date.now()<deadline){
  const value=await command('Runtime.evaluate',{expression:'document.body && document.body.getAttribute("data-probe-result")',returnByValue:true});
  if(value.result?.result?.value){const result=JSON.parse(value.result.result.value);if(!result.passed)throw Error(result.error);return result;}
  await delay(200);
 }
 throw Error('Browser probe did not finish in 60 seconds.');
}
(async()=>{
 let report;
 try{report={checked_at_utc:new Date().toISOString(),...await run(),cloud_requests:0};}
 catch(error){report={checked_at_utc:new Date().toISOString(),passed:false,error:error.message};process.exitCode=1;}
 finally{
  ws?.close();if(child?.pid)spawnSync('taskkill.exe',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
  server?.closeAllConnections();server?.close();
  // Remove only the exact profile created above, inside the verified cache root.
  if(path.dirname(profile)===path.resolve('.cache')&&path.basename(profile).startsWith('browser-storage-chrome-')){
   try{fs.rmSync(profile,{recursive:true,force:true,maxRetries:3,retryDelay:100});}catch{}
  }
 }
 fs.writeFileSync('.cache/browser-storage-smoke.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
})();
