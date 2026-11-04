import type {ApiDependencies} from './companion_api.ts';
import {ApiError,requiredString} from './errors.ts';
import {cors,errorResponse,jsonBody} from './http.ts';
import {decodeSubscription,purchaseHash,PurchaseCipher} from './play_billing.ts';
import type {PlayBillingProvider} from './play_billing.ts';

interface BillingState {available:boolean;account_ref?:string;product_id?:string;base_plan_id?:string;[key:string]:unknown}
export class BillingService {
 constructor(readonly deps:ApiDependencies,readonly provider:PlayBillingProvider,readonly cipher:PurchaseCipher,readonly enabled:boolean){}
 async status(owner:string){
  const state=await this.deps.db.rpc<BillingState>('morrow_billing_status',{p_owner:owner});
  return {...state,available:state.available&&this.enabled&&this.provider.configured&&this.cipher.configured};
 }
 async verify(owner:string,token:string){
  const state=await this.status(owner);
  if(!state.available||!state.account_ref||!state.product_id||!state.base_plan_id)
   throw new ApiError(503,'billing_unavailable','Purchases are not enabled yet.');
  await this.deps.db.rpc('morrow_billing_attempt',{p_owner:owner});
  const started=new Date().toISOString(),hash=await purchaseHash(token);
  let raw:unknown;
  try{raw=await this.provider.read(token);}catch(error){
   if(error instanceof ApiError&&error.code==='invalid_purchase'){
    const known=await this.deps.db.rpc<{owner:string}|null>('morrow_subscription_owner',{p_hash:hash});
    if(known?.owner===owner)return this.deps.db.rpc<BillingState>('morrow_invalidate_subscription',{p_owner:owner,p_hash:hash,p_verified_at:started});
   }
   throw error;
  }
  const purchase=decodeSubscription(raw,state.account_ref,state.product_id,state.base_plan_id);
  // Grant access only after server verification and acknowledgement. The app's
  // purchase status, product price and claimed owner are never trusted.
  if(!purchase.acknowledged&&['active','grace','canceled'].includes(purchase.state)&&Date.parse(purchase.expires??'')>Date.now()){
   await this.provider.acknowledge(purchase.product,token);purchase.acknowledged=true;
  }
  const encrypted=await this.cipher.encrypt(token,owner,hash);
  return this.deps.db.rpc<BillingState>('morrow_apply_subscription',{p_owner:owner,p_account_ref:state.account_ref,p_token_hash:hash,
   p_linked_hash:purchase.linkedToken?await purchaseHash(purchase.linkedToken):null,p_encrypted_token:encrypted,
   p_product:purchase.product,p_base_plan:purchase.basePlan,p_state:purchase.state,p_expires:purchase.expires,
   p_acknowledged:purchase.acknowledged,p_auto_renew:purchase.autoRenew,p_verified_at:started});
 }
 async refresh(owner:string){
  const status=await this.status(owner);if(!status.available)return status;
  const {subscriptions}=await this.deps.db.rpc<{subscriptions:{token_hash:string;encrypted_token:string}[]}>('morrow_subscription_tokens',{p_owner:owner});
  for(const s of subscriptions){const token=await this.cipher.decrypt(s.encrypted_token,owner,s.token_hash);await this.verify(owner,token);}
  return this.status(owner);
 }
}
export function createBillingApi(service:BillingService){
 return async(request:Request)=>{
  let headers=new Headers({'Cache-Control':'no-store'});
  try{
   headers=cors(request,service.deps.origins);
   if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
   if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','POST is required.');
   const identity=await service.deps.verify(request);await service.deps.eligible?.(identity.uid);
   const body=await jsonBody(request);let status:BillingState;
   if(body.action==='billing_status'||body.action==='billing_prepare')status=await service.status(identity.uid);
   else if(body.action==='billing_refresh')status=await service.refresh(identity.uid);
   else if(body.action==='billing_verify')status=await service.verify(identity.uid,requiredString(body.purchase_token,'purchase token',6000));
   else throw new ApiError(400,'unknown_action','Unknown billing action.');
   return Response.json(status,{headers});
  }catch(error){return errorResponse(error,headers);}
 };
}
