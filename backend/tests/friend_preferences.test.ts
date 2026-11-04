import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {database,rpc} from './database.ts';
import {friendPreferencesInput} from '../../supabase/functions/_shared/friend_preferences.ts';
import {companionInstructions} from '../../supabase/functions/_shared/openai.ts';
import {createConversationTurn} from '../../supabase/functions/_shared/conversation_turn.ts';
import {PostgresApi} from '../../supabase/functions/_shared/database.ts';

async function person(db:any,owner:string,age='25_34'){
 await rpc(db,'morrow_bootstrap',{p_owner:owner});
 await rpc(db,'morrow_save_named_profile',{p_owner:owner,p_username:owner,p_preferred_name:'Marvin',p_display_name:null,p_timezone:'Africa/Kampala',p_language:'en',p_location:null});
 await rpc(db,'morrow_save_introduction',{p_owner:owner,p_age_group:age,p_language:'en',p_timezone:'Africa/Kampala'});
 const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:owner,p_name:'Lumi',p_style:'Gentle & warm',p_interests:[],p_response_length:.5,p_memory_enabled:true,p_retention_days:null});
 return companion;
}
const choices={name:'Alex',personality_keys:['warm_caring','funny_playful'],support_preferences:['daily_companionship','emotional_support','learning','motivation'],
 interaction_style:'direct',learning_interests:'Practise German',personal_goals:'Be more confident speaking',additional_information:'I enjoy drawing'};

test('three different configurations reach fresh turn claims, retain names/goals across sessions and respect updates',async()=>{
 const db=await database();try{
  const configs=[choices,
   {...choices,name:'Sam',personality_keys:['calm_understanding','curious_intellectual'],support_preferences:['learning'],interaction_style:'thoughtful_detailed'},
   {...choices,name:'Jamie',personality_keys:['positive_motivating','casual_relaxed'],support_preferences:[],interaction_style:'casual_natural'}];
  for(const [index,config] of configs.entries()){
   const owner='tester_'+index,c=await person(db,owner,index===2?'55_plus':'25_34');
   await rpc(db,'morrow_save_friend_preferences',{p_owner:owner,p_companion:c.id,...friendPreferencesInput(config)});
   const restored=await rpc<any>(db,'morrow_bootstrap',{p_owner:owner});
   assert.equal(restored.companion.name,config.name);assert.deepEqual(restored.companion.personality_keys,config.personality_keys);
   assert.equal(restored.profile.preferred_name,'Marvin');assert.equal(restored.companion.personal_goals,config.personal_goals);
   const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:owner,p_companion:c.id});
   const request=randomUUID(),claim=await rpc<any>(db,'morrow_begin_turn',{p_owner:owner,p_conversation:conversation.id,p_request:request,p_content:'Can we practise something together?'});
   const context=await rpc<any>(db,'morrow_personal_context',{p_owner:owner,p_companion:c.id,p_conversation:conversation.id});
   const instructions=companionInstructions(claim.companion,[],null,context);
   assert.ok(instructions.includes(config.name));assert.ok(instructions.includes('Marvin'));assert.ok(instructions.includes('Practise German'));
   assert.ok(instructions.includes(config.interaction_style==='direct'?'short, clear replies':config.interaction_style==='thoughtful_detailed'?'thoughtful detail':'casual, natural'));
   assert.ok(instructions.includes(context.identity.age_group));
   await rpc(db,'morrow_complete_turn',{p_owner:owner,p_request:request,p_lease:claim.lease,p_content:'A synthetic persisted reply.'});
   const updated={...config,name:'Taylor',interaction_style:'calm_gentle',learning_interests:'Practise French',personal_goals:''};
   await rpc(db,'morrow_save_friend_preferences',{p_owner:owner,p_companion:c.id,...friendPreferencesInput(updated)});
   const next=await rpc<any>(db,'morrow_begin_turn',{p_owner:owner,p_conversation:conversation.id,p_request:randomUUID(),p_content:'What shall we practise?'});
   const prompt=companionInstructions(next.companion,[],null,context);
   assert.ok(prompt.includes('Practise French'));assert.ok(!prompt.includes('Practise German'));
   assert.equal(next.companion.name,'Taylor');assert.equal(next.companion.personal_goals,'');
  }
 }finally{await db.close();}
});

test('preferences enforce limits in API and SQL, preserve legacy consent and cannot change another owner',async()=>{
 const db=await database();try{
  const alice=await person(db,'alice'),bob=await person(db,'bobby');
  const args={p_owner:'alice',p_companion:alice.id,...friendPreferencesInput(choices)};
  const saved=await rpc<any>(db,'morrow_save_friend_preferences',args);
  assert.equal(saved.companion.consent_version,alice.consent_version);assert.equal(saved.companion.learning_enabled,false);
  await assert.rejects(rpc(db,'morrow_save_friend_preferences',{...args,p_companion:bob.id}),/not_found/);
  for(const invalid of [{support_preferences:['learning','motivation','friendship','creativity','productivity']},
   {personality_keys:[]},{personality_keys:['warm_caring','warm_caring']},{interaction_style:'ignore_safety'},{personal_goals:'x'.repeat(601)}])
   assert.throws(()=>friendPreferencesInput({...choices,...invalid}));
  for(const invalid of [{p_support:['learning','motivation','friendship','creativity','productivity']},
   {p_personalities:[]},{p_personalities:['warm_caring','warm_caring']},{p_communication:'ignore_safety'},{p_goals:'x'.repeat(601)}])
   await assert.rejects(rpc(db,'morrow_save_friend_preferences',{...args,...invalid}));
  const legacy=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Alex',p_style:'Playful',p_interests:['Music'],p_response_length:.5,p_memory_enabled:true,p_retention_days:null});
  assert.equal(legacy.companion.learning_interests,'Practise German');
  await db.exec(`set role authenticated; set request.jwt.claims='{"sub":"bobby","iss":"https://securetoken.google.com/morrow","firebase":{"sign_in_provider":"password"}}'`);
  const own=await db.query<any>('select name,personal_goals from public.companions');
  assert.equal(own.rows.length,1);assert.equal(own.rows[0].name,'Lumi');
  await assert.rejects(db.query('select public.morrow_save_friend_preferences($1,$2,$3,$4,$5,$6,$7,$8,$9)',Object.values(args)),/permission denied/);
  await db.exec('reset role');
 }finally{await db.close();}
});

test('younger-user selections cannot bypass backend eligibility or reach a provider through text or greeting requests',async()=>{
 const db=await database();let calls=0;
 try{
  await rpc(db,'morrow_bootstrap',{p_owner:'young_test'});
  await rpc(db,'morrow_save_named_profile',{p_owner:'young_test',p_username:'young_test',p_preferred_name:'Fictional',p_display_name:null,p_timezone:null,p_language:null,p_location:null});
  for(const age of ['under_13','13_15','16_17'])await assert.rejects(rpc(db,'morrow_save_introduction',{p_owner:'young_test',p_age_group:age,p_language:'en',p_timezone:'UTC'}),/invalid_input/);
  const mapped=new PostgresApi('https://db.test','test',async(_url,init)=>{
   try{return Response.json(await rpc(db,'morrow_require_eligible',JSON.parse(String(init?.body))));}
   catch(error){return Response.json({message:(error as Error).message},{status:400});}
  });
  const handler=createConversationTurn({origins:[],verify:async()=>({uid:'young_test'}),db:mapped,
   eligible:async owner=>{await mapped.rpc('morrow_require_eligible',{p_owner:owner});},ai:{async *reply(){calls++;yield 'Must never be generated';}}});
  for(const initiate of [false,true]){
   const response=await handler(new Request('https://local.test',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({conversation_id:randomUUID(),request_id:randomUUID(),content:'Hello',initiate,age_group:'25_34'})}));
   assert.equal(response.status,403);assert.equal((await response.json()).code,'introduction_required');
  }
  assert.equal(calls,0);
 }finally{await db.close();}
});
