import type { Identity } from './auth.ts';
import type { IdentityAdmin } from './firebase_admin.ts';
import type { Database } from './database.ts';
import { ApiError,requiredString,uuid } from './errors.ts';
import { cors,errorResponse,jsonBody } from './http.ts';

export async function processErasure(db:Database,admin:IdentityAdmin,owner:string):Promise<void>{
  const {job}=await db.rpc<{job:{lease:string}|null}>('morrow_claim_erasure',{p_owner:owner});
  if(!job)return;
  try{
    await db.rpc('morrow_erase_application_data',{p_owner:owner,p_lease:job.lease});
    await admin.erase(owner);
    await db.rpc('morrow_finish_erasure',{p_owner:owner,p_lease:job.lease,p_complete:true});
  }catch(error){
    await db.rpc('morrow_finish_erasure',{p_owner:owner,p_lease:job.lease,p_complete:false}).catch(()=>{});
    throw error;
  }
}
export function createPrivacyApi(deps:{db:Database;admin:IdentityAdmin;verify:(request:Request)=>Promise<Identity>;
  projectId:string;origins:string[];guardIdentity?:(identity:Identity)=>Promise<unknown>;defer?:(work:Promise<void>)=>void}){
  return async(request:Request):Promise<Response>=>{
    let headers=new Headers({'Cache-Control':'no-store'});
    try{
      headers=cors(request,deps.origins);
      if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
      if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','POST is required.');
      const identity=await deps.verify(request),body=await jsonBody(request);
      const args={p_owner:identity.uid};
      if(body.action==='erasure_status')return Response.json(await deps.db.rpc('morrow_account_status',args),{headers});
      await deps.guardIdentity?.(identity);
      if(body.action==='request_account_erasure'){
        if(body.confirmation!=='DELETE_MY_ACCOUNT')throw new ApiError(400,'confirmation_required','Please confirm account removal.');
        const now=Math.floor(Date.now()/1000),recent=identity.anonymous?identity.issuedAt:identity.authTime;
        if(!recent||recent>now+5||now-recent>300)throw new ApiError(401,'recent_login_required','Please sign in again before removing your account.');
        const status=await deps.db.rpc<{blocked:boolean;status:string}>('morrow_account_status',args);
        if(!status.blocked)await deps.admin.active(identity,true);
        const result=await deps.db.rpc('morrow_request_erasure',args);
        const work=processErasure(deps.db,deps.admin,identity.uid).catch(()=>console.error('account_erasure_pending'));
        if(deps.defer)deps.defer(work);else await work;
        return Response.json(result,{status:202,headers});
      }
      await deps.admin.active(identity,true);
      await deps.db.rpc('morrow_guard_account',{...args,p_project:deps.projectId});
      if(body.action==='export_data'){
        const section=requiredString(body.section,'section',30);
        const after=body.after==null?'':requiredString(body.after,'cursor',200);
        const result=section==='reports'?await deps.db.rpc('morrow_report_export',{...args,p_after:after}):
          ['subscriptions','usage'].includes(section)?await deps.db.rpc('morrow_billing_export',{...args,p_section:section,p_after:after}):
          await deps.db.rpc('morrow_export_page',{...args,p_section:section,p_after:after});
        return Response.json(result,{headers});
      }
      if(body.action==='set_conversation_retention'){
        if(body.days!==null&&(!Number.isInteger(body.days)||(body.days as number)<1||(body.days as number)>3650))
          throw new ApiError(400,'invalid_input','Choose a retention period.');
        return Response.json(await deps.db.rpc('morrow_set_conversation_retention',{
          ...args,p_companion:uuid(body.companion_id),p_days:body.days}),{headers});
      }
      throw new ApiError(400,'unknown_action','Unknown privacy action.');
    }catch(error){return errorResponse(error,headers);}
  };
}
