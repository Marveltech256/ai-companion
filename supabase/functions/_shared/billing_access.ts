import type {Database} from './database.ts';
import type {ApiDependencies} from './companion_api.ts';
import {ApiError} from './errors.ts';
import {BillingService} from './billing_api.ts';
import {GooglePlayBilling,PurchaseCipher} from './play_billing.ts';

// Refresh a potentially stale paid entitlement before denying a protected claim.
// Claims fail/roll back before model work, so this retry adds no AI request and
// never duplicates usage. A store failure grants nothing and remains retryable.
export function refreshingAccessDatabase(db:Database,refresh?:((owner:string)=>Promise<unknown>)):Database {
 if(!refresh)return db;
 const claims=new Set(['morrow_access_begin_turn','morrow_access_begin_greeting','morrow_access_voice']);
 return {async rpc<T>(name:string,args:Record<string,unknown>):Promise<T>{
  try{return await db.rpc<T>(name,args);}catch(error){
   if(!claims.has(name)||!(error instanceof ApiError)||
    !['subscription_required','usage_limit'].includes(error.code)||typeof args.p_owner!=='string')throw error;
   await refresh(args.p_owner);
   return db.rpc<T>(name,args);
  }
 }};
}
export function billingAccessDatabase(deps:ApiDependencies,get:(name:string)=>string|undefined):Database {
 if(get('BILLING_FEATURE_ENABLED')!=='true')return deps.db;
 const provider=new GooglePlayBilling(get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON')??'',get('FIREBASE_PROJECT_ID')??'','com.aipersonalcompanion');
 const service=new BillingService(deps,provider,new PurchaseCipher(get('BILLING_TOKEN_ENCRYPTION_KEY')??''),true);
 return refreshingAccessDatabase(deps.db,owner=>service.refresh(owner));
}
