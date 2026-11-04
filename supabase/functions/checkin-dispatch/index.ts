import { PostgresApi } from '../_shared/database.ts';
import { GoogleServiceAccount } from '../_shared/google.ts';
import { FirebasePush,createCheckinDispatcher } from '../_shared/checkins.ts';
import { createTextAi } from '../_shared/text_ai.ts';
import { proactiveWriter } from '../_shared/proactive.ts';
const db=new PostgresApi(Deno.env.get('SUPABASE_URL')??'',Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'');
const account=new GoogleServiceAccount(Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')??'',Deno.env.get('FIREBASE_PROJECT_ID')??'');
const ai=createTextAi(name=>Deno.env.get(name));
const write=proactiveWriter(db,ai);
Deno.serve(createCheckinDispatcher(db,new FirebasePush(account),Deno.env.get('SCHEDULER_SECRET')??'',async(job)=>{
 await db.rpc('morrow_require_friend_mode',{p_owner:job.owner_id});return write(job);
}));
