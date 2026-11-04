import {GoogleServiceAccount} from './google.ts';
import {ApiError} from './errors.ts';
import {boundedBody} from './http.ts';

export interface VerifiedSubscription {product:string;basePlan:string;state:string;expires:string|null;acknowledged:boolean;autoRenew:boolean;linkedToken?:string}
const unavailable=()=>new ApiError(503,'billing_unavailable','Purchases could not be checked just now. Please try again.');
export function decodeSubscription(value:any,account:string,product:string,basePlan:string):VerifiedSubscription {
 if(value.externalAccountIdentifiers?.obfuscatedExternalAccountId!==account)
  throw new ApiError(409,'purchase_conflict','This purchase belongs to a different companion account.');
 const line=(value.lineItems??[]).find((item:any)=>item.productId===product&&item.offerDetails?.basePlanId===basePlan);
 if(!line)throw new ApiError(400,'invalid_purchase','The purchased plan does not match the available subscription.');
 const states:Record<string,string>={SUBSCRIPTION_STATE_PENDING:'pending',SUBSCRIPTION_STATE_ACTIVE:'active',
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD:'grace',SUBSCRIPTION_STATE_CANCELED:'canceled',SUBSCRIPTION_STATE_EXPIRED:'expired',
  SUBSCRIPTION_STATE_PAUSED:'paused',SUBSCRIPTION_STATE_ON_HOLD:'hold',SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED:'revoked'};
 const state=states[value.subscriptionState];if(!state)throw unavailable();
 const expiry=typeof line.expiryTime==='string'&&Number.isFinite(Date.parse(line.expiryTime))?line.expiryTime:null;
 if(['active','grace','canceled'].includes(state)&&!expiry)throw unavailable();
 return {product,basePlan,state,expires:expiry,acknowledged:value.acknowledgementState==='ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
  autoRenew:line.autoRenewingPlan?.autoRenewEnabled===true,
  linkedToken:typeof value.linkedPurchaseToken==='string'?value.linkedPurchaseToken:undefined};
}
export interface PlayBillingProvider {
 readonly configured:boolean;
 read(token:string):Promise<unknown>;
 acknowledge(product:string,token:string):Promise<void>;
}
export class GooglePlayBilling implements PlayBillingProvider {
 readonly configured:boolean;
 private account:GoogleServiceAccount;
 constructor(json:string,project:string,private packageName:string,private fetcher=fetch){
  this.configured=!!json;this.account=new GoogleServiceAccount(json,project,fetcher);
 }
 private async request(path:string,method='GET'){
  if(!this.configured)throw unavailable();
  const token=await this.account.token('https://www.googleapis.com/auth/androidpublisher');
  const response=await this.fetcher(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(this.packageName)}/${path}`,{
   method,headers:{Authorization:`Bearer ${token}`,...(method==='POST'?{'Content-Type':'application/json'}:{})},
   ...(method==='POST'?{body:'{}'}:{}),signal:AbortSignal.timeout(15000)});
  if(!response.ok){await response.body?.cancel();
   if(response.status===404||response.status===410)throw new ApiError(400,'invalid_purchase','This purchase could not be verified.');
   throw unavailable();}
  return response;
 }
 async read(token:string):Promise<unknown>{
  const response=await this.request(`purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`);
  return JSON.parse(new TextDecoder().decode(await boundedBody(response,131072)));
 }
 async acknowledge(product:string,token:string){
  const r=await this.request(`purchases/subscriptions/${encodeURIComponent(product)}/tokens/${encodeURIComponent(token)}:acknowledge`,'POST');
  await r.body?.cancel();
 }
}

const encode=(b:Uint8Array)=>btoa(String.fromCharCode(...b)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
const decode=(s:string)=>Uint8Array.from(atob(s.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));
export async function purchaseHash(value:string):Promise<string>{
 return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(b=>b.toString(16).padStart(2,'0')).join('');
}
export class PurchaseCipher {
 readonly configured:boolean;
 constructor(private secret:string){this.configured=/^[A-Za-z0-9_-]{43}$/.test(secret);}
 private async key(){
  if(!this.configured)throw unavailable();const bytes=decode(this.secret);
  if(bytes.length!==32)throw unavailable();return crypto.subtle.importKey('raw',bytes,'AES-GCM',false,['encrypt','decrypt']);
 }
 async encrypt(token:string,owner:string,hash:string){
  const iv=crypto.getRandomValues(new Uint8Array(12)),data=await crypto.subtle.encrypt({name:'AES-GCM',iv,
   additionalData:new TextEncoder().encode(`${owner}:${hash}`)},await this.key(),new TextEncoder().encode(token));
  return JSON.stringify({v:1,iv:encode(iv),data:encode(new Uint8Array(data))});
 }
 async decrypt(encrypted:string,owner:string,hash:string){
  const value=JSON.parse(encrypted);if(value.v!==1||typeof value.iv!=='string'||typeof value.data!=='string')throw unavailable();
  const data=await crypto.subtle.decrypt({name:'AES-GCM',iv:decode(value.iv),additionalData:new TextEncoder().encode(`${owner}:${hash}`)},
   await this.key(),decode(value.data));return new TextDecoder().decode(data);
 }
}
