// Serve only the compiled Flutter app on loopback for local PC testing.
import http from 'node:http';
import path from 'node:path';
import {readFile,stat} from 'node:fs/promises';
const root=path.resolve('build/web');
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.ico':'image/x-icon','.ttf':'font/ttf','.woff2':'font/woff2','.svg':'image/svg+xml'};
await stat(path.join(root,'index.html'));
http.createServer(async(req,res)=>{
 try{
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);res.end();return;}
  const url=new URL(req.url,'http://localhost:52100');
  const target=path.resolve(root,'.'+decodeURIComponent(url.pathname));
  if(target!==root&&!target.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  const file=target===root?path.join(root,'index.html'):target;
  const bytes=await readFile(file);
  res.writeHead(200,{'Content-Type':types[path.extname(file)]??'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(req.method==='HEAD'?undefined:bytes);
 }catch{res.writeHead(404);res.end('Not found');}
}).listen(52100,'127.0.0.1',()=>console.log('Ai Companion is running at http://localhost:52100'));
