import {runtime} from '../_shared/runtime.ts';
import {createReviewAccess,createReviewSigner} from '../_shared/review_access.ts';
const get=(name:string)=>Deno.env.get(name);
const deps=runtime(get);
Deno.serve(createReviewAccess({...deps,enabled:get('REVIEW_GUEST_ENABLED')==='true',codeHash:get('REVIEW_GUEST_CODE_HASH')??'',
 sign:createReviewSigner(get('FIREBASE_SERVICE_ACCOUNT_JSON')??'',get('FIREBASE_PROJECT_ID')??'')}));
