import type { Database } from './database.ts';
import { GoogleServiceAccount } from './google.ts';
import { ApiError } from './errors.ts';

export interface Job {id:string;lease:string;owner_id:string;companion_id?:string;reason?:string;devices:{installation_id:string;token:string}[]}
export interface PushRoute {checkin_id:string;conversation_id:string}
export interface PushSender {send(token:string,collapseId:string,ttlSeconds?:number,route?:PushRoute):Promise<'sent'|'invalid'|'unknown'|'suppressed'>}
export class FirebasePush implements PushSender {
  constructor(private account:GoogleServiceAccount,private fetcher=fetch){}
  async send(token:string,collapseId:string,ttlSeconds=300,route?:PushRoute):Promise<'sent'|'invalid'|'unknown'|'suppressed'>{
    const deadline=Date.now()+ttlSeconds*1000;
    const access=await this.account.token('https://www.googleapis.com/auth/firebase.messaging');
    ttlSeconds=Math.floor((deadline-Date.now())/1000);
    if(ttlSeconds<=0)return 'suppressed';
    const payload={message:{token,
      notification:{title:'Ai Companion',body:'A little space for you, whenever you feel like talking.'},
      data:{screen:'conversation',...route},
      android:{collapse_key:collapseId,ttl:`${ttlSeconds}s`,priority:'NORMAL'},
      apns:{headers:{'apns-collapse-id':collapseId,'apns-priority':'5','apns-expiration':String(Math.floor(Date.now()/1000)+ttlSeconds)}}}};
    try{
      const response=await this.fetcher(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(this.account.projectId)}/messages:send`,{
        method:'POST',headers:{Authorization:`Bearer ${access}`,'Content-Type':'application/json'},
        body:JSON.stringify(payload),signal:AbortSignal.timeout(15000)});
      if(response.ok){await response.body?.cancel();return 'sent';}
      const body=await response.json().catch(()=>({}));
      return body.error?.details?.some((x:{errorCode?:string})=>x.errorCode==='UNREGISTERED')?'invalid':'unknown';
    }catch{return 'unknown';}
  }
}

export function sameSecret(a:string,b:string):boolean{
  const left=new TextEncoder().encode(a),right=new TextEncoder().encode(b);
  let difference=left.length^right.length;
  for(let i=0;i<Math.max(left.length,right.length);i++)difference|=(left[i]??0)^(right[i]??0);
  return difference===0;
}
export function createCheckinDispatcher(db:Database,push:PushSender,secret:string,prepare?:(job:Job)=>Promise<PushRoute>){
  return async(request:Request):Promise<Response>=>{
    if(!secret || !sameSecret(request.headers.get('authorization')??'',`Bearer ${secret}`))
      return Response.json({code:'unauthenticated'},{status:401,headers:{'Cache-Control':'no-store'}});
    if(request.method!=='POST')return new Response(null,{status:405});
    try{
      const {jobs}=await db.rpc<{jobs:Job[]}>('morrow_due_checkins',{});
      let sent=0;
      for(const job of jobs){
        const {allowed,ttl_seconds}=await db.rpc<{allowed:boolean;ttl_seconds:number}>('morrow_authorize_checkin',{p_id:job.id,p_lease:job.lease});
        let status='suppressed';
        if(allowed && ttl_seconds>0){
          let route:PushRoute|undefined;
          if(prepare && job.companion_id){
            try{route=await prepare(job);}catch{
              await db.rpc('morrow_finish_checkin',{p_id:job.id,p_lease:job.lease,p_status:'failed'});continue;
            }
          }
          status='failed';
          for(const device of job.devices){
            try{
              const current=await db.rpc<{allowed:boolean;ttl_seconds:number}>('morrow_authorize_checkin',{
                p_id:job.id,p_lease:job.lease});
              if(!current.allowed||current.ttl_seconds<=0){if(status!=='sent')status='suppressed';break;}
              const result=await push.send(device.token,job.id,Math.min(current.ttl_seconds,300),route);
              if(result==='invalid')await db.rpc('morrow_unregister_device',{
                p_owner:job.owner_id,p_installation:device.installation_id});
              else if(result==='sent'){status='sent';sent++;}
              else if(status!=='sent')status=result==='suppressed'?'suppressed':'unknown';
            }catch{if(status!=='sent')status='failed';}
          }
        }
        await db.rpc('morrow_finish_checkin',{p_id:job.id,p_lease:job.lease,p_status:status});
      }
      return Response.json({processed:jobs.length,sent,provider_accepted:sent,delivery_confirmed:0},{headers:{'Cache-Control':'no-store'}});
    }catch(error){
      const status=error instanceof ApiError?error.status:503;
      return Response.json({code:'dispatch_unavailable'},{status,headers:{'Cache-Control':'no-store'}});
    }
  };
}
