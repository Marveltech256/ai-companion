import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database,rpc } from './database.ts';
import { companionInstructions } from '../../supabase/functions/_shared/openai.ts';

test('learning is opt-in, counts actual completed turns once, and clears on opt-out',async()=>{
  const db=await database();
  try{
    await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
    const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'alice',p_name:'Lumi',
      p_style:'Reflective',p_interests:['Books'],p_response_length:.5,p_memory_enabled:false,p_retention_days:null});
    const {conversation}=await rpc<any>(db,'morrow_create_conversation',{p_owner:'alice',p_companion:companion.id});
    const turn=async()=>{
      const request=randomUUID();const args={p_owner:'alice',p_conversation:conversation.id,p_request:request,p_content:'I enjoy books.'};
      const claim=await rpc<any>(db,'morrow_begin_turn',args);
      await rpc(db,'morrow_complete_turn',{p_owner:'alice',p_request:request,p_lease:claim.lease,p_content:'What do you like reading?'});
      await rpc(db,'morrow_begin_turn',args);
    };
    await turn();
    assert.equal((await rpc<any>(db,'morrow_personalization',{p_owner:'alice',p_companion:companion.id})).observations,null);
    await rpc(db,'morrow_set_learning',{p_owner:'alice',p_companion:companion.id,p_enabled:true});
    await turn();
    const result=await rpc<any>(db,'morrow_personalization',{p_owner:'alice',p_companion:companion.id});
    assert.equal(result.observations.completed_turns,1);
    assert.equal(result.observations.average_user_characters,14);
    await assert.rejects(rpc(db,'morrow_personalization',{p_owner:'bob',p_companion:companion.id}),/not_found/);
    await rpc(db,'morrow_set_learning',{p_owner:'alice',p_companion:companion.id,p_enabled:false});
    assert.equal((await db.query('select * from public.interaction_patterns')).rows.length,0);
    const prompt=companionInstructions(companion,[],{completed_turns:999,average_user_characters:999});
    assert.ok(prompt.includes('Books'));assert.ok(!prompt.includes('999'));
  }finally{await db.close();}
});
