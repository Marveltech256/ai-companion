import { runtime } from '../_shared/runtime.ts';
import { processErasure } from '../_shared/privacy.ts';
import { sameSecret } from '../_shared/checkins.ts';
const dependencies=runtime(name=>Deno.env.get(name));
const secret=Deno.env.get('SCHEDULER_SECRET')??'';
Deno.serve(async(request:Request)=>{
 if(!secret||!sameSecret(request.headers.get('authorization')??'',`Bearer ${secret}`))
  return Response.json({code:'unauthenticated'},{status:401,headers:{'Cache-Control':'no-store'}});
 if(request.method!=='POST')return new Response(null,{status:405});
 try{
  await dependencies.db.rpc('morrow_review_cleanup',{});
  const {owners}=await dependencies.db.rpc<{owners:string[]}>('morrow_pending_erasures',{});
  for(const owner of owners)await processErasure(dependencies.db,dependencies.admin,owner).catch(()=>console.error('erasure_retry_pending'));
  await dependencies.db.rpc('morrow_privacy_cleanup',{});
  await dependencies.db.rpc('morrow_report_cleanup',{});
  await dependencies.db.rpc('morrow_billing_cleanup',{});
  return Response.json({processed:owners.length},{headers:{'Cache-Control':'no-store'}});
 }catch{return Response.json({code:'maintenance_unavailable'},{status:503,headers:{'Cache-Control':'no-store'}});}
});
