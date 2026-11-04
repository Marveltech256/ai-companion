import {runtime} from '../_shared/runtime.ts';
import {GooglePlayBilling,PurchaseCipher} from '../_shared/play_billing.ts';
import {BillingService} from '../_shared/billing_api.ts';
import {createBillingNotifications,verifyBillingPush} from '../_shared/billing_notifications.ts';
const deps=runtime(name=>Deno.env.get(name));
const service=new BillingService(deps,new GooglePlayBilling(Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON')??'',Deno.env.get('FIREBASE_PROJECT_ID')??'','com.aipersonalcompanion'),
 new PurchaseCipher(Deno.env.get('BILLING_TOKEN_ENCRYPTION_KEY')??''),Deno.env.get('BILLING_FEATURE_ENABLED')==='true');
Deno.serve(createBillingNotifications(service,request=>verifyBillingPush(request,Deno.env.get('GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT_EMAIL')??'',Deno.env.get('GOOGLE_PLAY_RTDN_AUDIENCE')??'')));
