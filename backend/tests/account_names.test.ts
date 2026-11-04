import {test} from 'node:test';
import assert from 'node:assert/strict';
import {database,rpc} from './database.ts';
test('account usernames are case-insensitive, owned, and saved atomically with preferred names',async()=>{
 const db=await database();try{
  for(const owner of ['alice','bob'])await rpc(db,'morrow_bootstrap',{p_owner:owner});
  const args={p_owner:'alice',p_username:'Marvin_20',p_preferred_name:'Marvin',p_display_name:null,p_timezone:'Africa/Kampala',p_language:'English',p_location:null};
  const first=await rpc<any>(db,'morrow_save_named_profile',args);assert.equal(first.profile.username,'marvin_20');assert.equal(first.profile.preferred_name,'Marvin');
  await assert.rejects(rpc(db,'morrow_save_named_profile',{...args,p_owner:'bob',p_preferred_name:'Robert'}),/username_taken/);
  const bob=await rpc<any>(db,'morrow_bootstrap',{p_owner:'bob'});assert.equal(bob.profile.username,null);assert.equal(bob.profile.preferred_name,null);
  await assert.rejects(rpc(db,'morrow_save_named_profile',{...args,p_username:'bad handle'}),/invalid_username/);
  const second=await rpc<any>(db,'morrow_save_named_profile',{...args,p_owner:'bob',p_username:'robert',p_preferred_name:'Bob'});assert.equal(second.profile.preferred_name,'Bob');
  const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Lumi',p_style:'Playful',p_interests:[],p_response_length:.5,p_memory_enabled:false,p_retention_days:null});
  assert.equal((await rpc<any>(db,'morrow_companion_context',{p_owner:'alice',p_companion:companion.id})).identity.preferred_name,'Marvin');
  await db.exec("set role authenticated;select set_config('request.jwt.claims','{\"sub\":\"bob\",\"iss\":\"https://securetoken.google.com/morrow\",\"firebase\":{\"sign_in_provider\":\"password\"}}',false)");
  const visible=await db.query('select username from public.profiles');assert.deepEqual(visible.rows,[{username:'robert'}]);
  await assert.rejects(db.query("select public.morrow_save_named_profile('alice','stolen','Bob',null,null,null,null)"),/permission denied/);
 }finally{await db.close();}
});
