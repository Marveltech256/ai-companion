import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPair,SignJWT} from 'jose';
import {database,rpc} from './database.ts';
import {verifyFirebase,requireRegisteredIdentity} from '../../supabase/functions/_shared/auth.ts';
import {createCompanionApi} from '../../supabase/functions/_shared/companion_api.ts';
import {BillingService,createBillingApi} from '../../supabase/functions/_shared/billing_api.ts';
import {PurchaseCipher} from '../../supabase/functions/_shared/play_billing.ts';
import {PostgresApi} from '../../supabase/functions/_shared/database.ts';
import {assessEuropeanAiSetup} from '../../tools/release_market_gate.mjs';

test('registered EU and US profiles can onboard, retain manual preferences and access the same free service',async()=>{
 const db=await database();
 try {
  const {publicKey,privateKey}=await generateKeyPair('RS256');
  const databaseApi=new PostgresApi('https://database.test','synthetic-server-key',async(input,init)=>{
   const name=new URL(String(input)).pathname.split('/').at(-1)!;
   try{return Response.json(await rpc(db,name,JSON.parse(String(init?.body))));}
   catch(error){return Response.json({message:(error as Error).message},{status:400});}
  });
  const deps={origins:['https://companion.test'],
   verify:async(request:Request)=>requireRegisteredIdentity(await verifyFirebase(request,'morrow',async()=>publicKey)),
   eligible:async(owner:string)=>{await databaseApi.rpc('morrow_require_eligible',{p_owner:owner});},
   db:databaseApi,
  };
  const api=createCompanionApi(deps);
  const billing=createBillingApi(new BillingService(deps,{configured:false,read:async()=>{throw new Error('No store requests in free testing.');},acknowledge:async()=>{}},new PurchaseCipher(''),false));
  const people=[
   {uid:'french_tester',country:'FR',zone:'Europe/Paris',language:'fr',location:'Paris'},
   {uid:'german_tester',country:'DE',zone:'Europe/Berlin',language:'de',location:'Berlin'},
   {uid:'us_tester',country:'US',zone:'America/Phoenix',language:'en',location:'Phoenix'},
  ];
  const saved=[];
  for(const person of people){
   const token=await new SignJWT({auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'password'}})
    .setProtectedHeader({alg:'RS256'}).setSubject(person.uid).setAudience('morrow')
    .setIssuer('https://securetoken.google.com/morrow').setIssuedAt().setExpirationTime('5m').sign(privateKey);
   const request=(body:Record<string,unknown>,country=person.country,handler=api)=>handler(new Request('https://api.test',{
    method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',Origin:'https://companion.test',
     'CF-IPCountry':country,'X-Country-Code':country,'Accept-Language':'en-US'},body:JSON.stringify(body),
   }));
   assert.equal((await request({action:'bootstrap'})).status,200);
   assert.equal((await request({action:'list_conversations'})).status,403);
   const profile=await request({action:'save_personal_profile',username:person.uid,preferred_name:'Fictional Tester',
    language:person.language,timezone:person.zone,general_location:person.location});
   assert.equal(profile.status,200);
   const intro=await request({action:'save_introduction',age_group:'25_34',language:person.language,timezone:person.zone,timezone_automatic:false});
   assert.equal(intro.status,200);
   const companionResponse=await request({action:'save_companion',name:'Lumi',style:'Gentle & warm',interests:[],
    response_length:.5,memory_enabled:true,retention_days:null});
   assert.equal(companionResponse.status,200);
   const {companion}=await companionResponse.json();
   const created=await request({action:'create_conversation',companion_id:companion.id,title:'Fictional access test'});
   assert.equal(created.status,200);const {conversation}=await created.json();saved.push({person,conversation});
   for(const headerCountry of ['FR','DE','US','XX']){
    const response=await request({action:'bootstrap'},headerCountry);
    assert.equal(response.status,200);assert.equal(response.headers.get('Location'),null);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'),'https://companion.test');
    const state=await response.json();
    assert.equal(state.profile.language,person.language);assert.equal(state.profile.timezone,person.zone);
    assert.equal(state.profile.timezone_automatic,false);
    const price=await request({action:'billing_status'},headerCountry,billing);
    assert.equal(price.status,200);
    assert.deepEqual(await price.json(),{mode:'free_testing',available:false,enforced:false,premium:false});
   }
   // Country headers cannot substitute another account's ownership or waive authentication.
   const foreign=saved.find(item=>item.person.uid!==person.uid);
   if(foreign){const denied=await request({action:'messages',conversation_id:foreign.conversation.id},foreign.person.country);
    assert.equal(denied.status,404);}
  }
  for(const country of ['FR','US']){
   const unauthenticated=await api(new Request('https://api.test',{method:'POST',headers:{'Content-Type':'application/json','CF-IPCountry':country},body:'{"action":"bootstrap"}'}));
   assert.equal(unauthenticated.status,401);
  }
 }finally{await db.close();}
});

test('European AI release gate requires a recent affirmative paid-project check and fails closed on missing evidence',()=>{
 const now=Date.parse('2026-11-04T12:00:00Z');
 const report={checked_at_utc:new Date(now).toISOString(),project:'ai-personal-companion',read_only:true,
  checks:[{service:'generativelanguage.googleapis.com',state:'ENABLED'},{check:'billing-status',billingEnabled:false}]};
 assert.deepEqual(assessEuropeanAiSetup(report,now),{paidSetupVerified:false,reason:'paid_api_setup_pending'});
 const paid={...report,checks:[report.checks[0],{check:'billing-status',billingEnabled:true}]};
 assert.deepEqual(assessEuropeanAiSetup(paid,now),{paidSetupVerified:true,reason:'paid_project_verified'});
 for(const invalid of [null,{}, {...paid,project:'another-project'}, {...paid,read_only:false},
  {...paid,checked_at_utc:new Date(now-86400001).toISOString()}, {...paid,checked_at_utc:new Date(now+60001).toISOString()},
  {...paid,checks:[{check:'billing-status',status:403}]}, {...paid,checks:[]}, {...paid,checks:{}}, {...paid,checks:null}])
  assert.equal(assessEuropeanAiSetup(invalid,now).paidSetupVerified,false);
 assert.equal(assessEuropeanAiSetup({...paid,checks:[{check:'billing-status',billingEnabled:true}]},now).paidSetupVerified,false);
});
