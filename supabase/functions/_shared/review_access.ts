import {importPKCS8,SignJWT} from 'jose';
import type {Database} from './database.ts';
import type {Identity} from './auth.ts';
import type {IdentityAdmin} from './firebase_admin.ts';
import {ApiError,requiredString} from './errors.ts';
import {cors,errorResponse,jsonBody} from './http.ts';
import {sameSecret} from './checkins.ts';

export async function reviewCodeHash(code:string){
 return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(code.trim())))).map(b=>b.toString(16).padStart(2,'0')).join('');
}
export function createReviewSigner(json:string,project:string){
 return async(uid:string,version:string)=>{
  let account:any;try{account=JSON.parse(json);}catch{throw new ApiError(503,'review_unavailable','Review access is not available.');}
  if(account.project_id!==project||!account.client_email||!account.private_key)throw new ApiError(503,'review_unavailable','Review access is not available.');
  const key=await importPKCS8(account.private_key,'RS256');
  return new SignJWT({uid,claims:{review_guest:true,review_version:version}}).setProtectedHeader({alg:'RS256',typ:'JWT'})
   .setIssuer(account.client_email).setSubject(account.client_email)
   .setAudience('https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit')
   .setIssuedAt().setExpirationTime('5m').sign(key);
 };
}
export async function guardReviewIdentity(db:Database,identity:Identity){
 if(identity.reviewGuest||identity.uid.startsWith('review_')){
  if(!identity.reviewGuest||!identity.reviewVersion)throw new ApiError(401,'review_access_ended','Guest review access has ended. Please sign in.');
  await db.rpc('morrow_review_guard',{p_owner:identity.uid,p_version:identity.reviewVersion});
 }
 return identity;
}
export function createReviewAccess(deps:{db:Database;admin:IdentityAdmin;verifyToken:(r:Request)=>Promise<Identity>;
 enabled:boolean;codeHash:string;origins:string[];sign:(uid:string,version:string)=>Promise<string>}){
 return async(request:Request)=>{
  let headers=new Headers({'Cache-Control':'no-store'});
  try{
   headers=cors(request,deps.origins);
   if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
   if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','POST is required.');
   const body=await jsonBody(request);
   if(body.action!=='status'&&body.action!=='enter')throw new ApiError(400,'unknown_action','Unknown review action.');
   const configured=deps.enabled&&/^[a-f0-9]{64}$/.test(deps.codeHash);
   const status=configured?await deps.db.rpc<{enabled:boolean;version:string}>('morrow_review_status',{}):{enabled:false,version:''};
   if(body.action==='status')return Response.json({enabled:status.enabled},{headers});
   if(!status.enabled)throw new ApiError(503,'review_unavailable','Guest review access is not available. Please sign in.');
   const code=requiredString(body.access_code,'review access code',160);
   if(!sameSecret(await reviewCodeHash(code),deps.codeHash))throw new ApiError(401,'invalid_review_code','The review access code was not accepted.');
   let owner:string;
   if(body.renew===true){
    const identity=await deps.verifyToken(request);
    if(!identity.reviewGuest)throw new ApiError(403,'review_only','Use guest review access first.');
    await guardReviewIdentity(deps.db,identity);await deps.admin.active(identity,true);owner=identity.uid;
   }else{
    owner=`review_${crypto.randomUUID()}`;
    await deps.db.rpc('morrow_review_begin',{p_owner:owner,p_version:status.version});
   }
   return Response.json({custom_token:await deps.sign(owner,status.version)},{headers});
  }catch(error){return errorResponse(error,headers);}
 };
}
