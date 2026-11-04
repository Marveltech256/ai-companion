import {createRemoteJWKSet,jwtVerify} from 'jose';
import {ApiError} from './errors.ts';
import {boundedBody} from './http.ts';
import {BillingService} from './billing_api.ts';
import {purchaseHash} from './play_billing.ts';
const keys=createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
export async function verifyBillingPush(request:Request,email:string,audience:string){
 if(!email||!audience)throw new ApiError(503,'billing_unavailable','Billing notifications are not configured.');
 const auth=request.headers.get('authorization')??'';if(!auth.startsWith('Bearer '))throw new ApiError(401,'unauthenticated','Authentication is required.');
 try{
  const {payload}=await jwtVerify(auth.slice(7),keys,{audience,issuer:['accounts.google.com','https://accounts.google.com'],algorithms:['RS256'],maxTokenAge:'1h'});
  if(payload.email!==email||payload.email_verified!==true)throw new Error('Wrong sender');
 }catch{throw new ApiError(401,'unauthenticated','Authentication is required.');}
}
export function createBillingNotifications(service:BillingService,verify:(request:Request)=>Promise<void>){
 return async(request:Request)=>{
  const headers={'Cache-Control':'no-store'};
  if(request.method!=='POST')return new Response(null,{status:405,headers});
  try{
   await verify(request);
   if(!service.enabled)return Response.json({code:'billing_unavailable'},{status:503,headers});
   const envelope=JSON.parse(new TextDecoder().decode(await boundedBody(request,65536)));
   const data=JSON.parse(atob(envelope.message?.data??''));
   if(data.packageName!=='com.aipersonalcompanion')return Response.json({code:'invalid_input'},{status:400,headers});
   if(data.testNotification)return new Response(null,{status:204,headers});
   const token=data.subscriptionNotification?.purchaseToken;
   if(typeof token!=='string'||!token||token.length>6000)return Response.json({code:'invalid_input'},{status:400,headers});
   const owner=await service.deps.db.rpc<{owner:string}|null>('morrow_subscription_owner',{p_hash:await purchaseHash(token)});
   // A notification is a prompt to recheck Google, never an entitlement itself.
   if(owner?.owner)await service.verify(owner.owner,token);
   return new Response(null,{status:204,headers});
  }catch(error){return Response.json({code:error instanceof ApiError?error.code:'billing_unavailable'},
   {status:error instanceof ApiError?error.status:503,headers});}
 };
}
