// Bound the browser harness and terminate only the process tree we started.
const fs=require('node:fs'),path=require('node:path'),{spawn,spawnSync}=require('node:child_process');
const log=fs.openSync('.cache/browser-storage-latest.log','w');
const child=spawn(process.env.ComSpec||'C:/Windows/System32/cmd.exe',[
 '/d','/c',`C:\\flutter\\bin\\flutter.bat ${process.argv.includes('--verbose')?'--verbose ':''}--suppress-analytics test --no-pub --platform chrome --timeout 45s test/browser_storage_test.dart --reporter expanded`
],{cwd:process.cwd(),env:process.env,windowsHide:true,stdio:['ignore',log,log]});
let timedOut=false;
const timeout=setTimeout(()=>{timedOut=true;spawnSync('taskkill.exe',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});},120000);
child.on('error',()=>{clearTimeout(timeout);process.exitCode=1;});
child.on('exit',code=>{
 clearTimeout(timeout);fs.closeSync(log);
 const report={checked_at_utc:new Date().toISOString(),exit_code:code,harness_timed_out:timedOut,passed:!timedOut&&code===0};
 fs.writeFileSync('.cache/browser-storage-latest.json',JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report));console.log(fs.readFileSync('.cache/browser-storage-latest.log','utf8').slice(-2400));
 process.exitCode=report.passed?0:1;
});
