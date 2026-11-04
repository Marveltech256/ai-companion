import {runtime} from '../_shared/runtime.ts';
import {GooglePlayBilling,PurchaseCipher} from '../_shared/play_billing.ts';
import {BillingService,createBillingApi} from '../_shared/billing_api.ts';
const deps=runtime(name=>Deno.env.get(name));
const provider=new GooglePlayBilling(Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON')??'',Deno.env.get('FIREBASE_PROJECT_ID')??'','com.aipersonalcompanion');
const service=new BillingService(deps,provider,new PurchaseCipher(Deno.env.get('BILLING_TOKEN_ENCRYPTION_KEY')??''),Deno.env.get('BILLING_FEATURE_ENABLED')==='true');
Deno.serve(createBillingApi(service));
