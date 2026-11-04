import { runtime } from '../_shared/runtime.ts';
import { createPrivacyApi } from '../_shared/privacy.ts';
const dependencies=runtime(name=>Deno.env.get(name));
declare const EdgeRuntime:{waitUntil(work:Promise<unknown>):void};
Deno.serve(createPrivacyApi({...dependencies,verify:dependencies.verifyToken,
  projectId:Deno.env.get('FIREBASE_PROJECT_ID')??'',defer:(work)=>EdgeRuntime.waitUntil(work)}));
