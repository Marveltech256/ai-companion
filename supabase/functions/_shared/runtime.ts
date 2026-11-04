import { verifyFirebase, requireRegisteredIdentity } from "./auth.ts";
import { PostgresApi } from "./database.ts";
import { GoogleServiceAccount } from './google.ts';
import { FirebaseIdentityAdmin } from './firebase_admin.ts';
import {audioCapabilities} from './audio_factory.ts';
import {guardReviewIdentity} from './review_access.ts';

export function runtime(get: (name: string) => string | undefined) {
  const required = (name: string) => {
    const value = get(name);
    if (!value) throw new Error(`Missing server environment variable ${name}`);
    return value;
  };
  const projectId = required("FIREBASE_PROJECT_ID");
  const db=new PostgresApi(required("SUPABASE_URL"), required("SUPABASE_SERVICE_ROLE_KEY"));
  const admin=new FirebaseIdentityAdmin(new GoogleServiceAccount(get('FIREBASE_SERVICE_ACCOUNT_JSON')??'',projectId));
  const verifyToken=async(request:Request)=>requireRegisteredIdentity(await verifyFirebase(request,projectId));
  return {
    db,admin,verifyToken,guardIdentity:(identity:import('./auth.ts').Identity)=>guardReviewIdentity(db,identity),
    eligible:async(owner:string)=>{await db.rpc('morrow_require_eligible',{p_owner:owner});},
    friendEligible:async(owner:string)=>{await db.rpc('morrow_require_friend_mode',{p_owner:owner});},
    capabilities:{...audioCapabilities(get),billing:get('BILLING_FEATURE_ENABLED')==='true'},
    verify: async(request:Request)=>{
      const identity=await verifyToken(request);
      await guardReviewIdentity(db,identity);
      await admin.active(identity);
      await db.rpc('morrow_guard_account',{p_owner:identity.uid,p_project:projectId});
      return identity;
    },
    origins: (get("ALLOWED_ORIGINS") ?? "").split(",").map(s => s.trim()).filter(Boolean),
  };
}
