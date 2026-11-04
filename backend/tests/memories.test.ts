import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { database,rpc } from './database.ts';
import { groundedCandidates } from '../../supabase/functions/_shared/memory.ts';

test('memory facts require a grounded quote and reject credentials',()=>{
  const candidate={key:'people.maya',category:'people',quote:'My sister is Maya.',confidence:.95,importance:.8};
  assert.equal(groundedCandidates({memories:[candidate]},'My sister is Maya.').length,1);
  assert.equal(groundedCandidates({memories:[candidate]},'I like music.').length,0);
  assert.equal(groundedCandidates({memories:[{...candidate,quote:'My password is abc.'}]},'My password is abc.').length,0);
  assert.equal(groundedCandidates({memories:[{...candidate,confidence:.2}]},'My sister is Maya.').length,0);
});

test('memories respect consent, edits, deletion tombstones, ownership and expiry',async()=>{
  const db=await database();
  try{
    await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
    const settings={p_owner:'alice',p_name:'Lumi',p_style:'Gentle & warm',p_interests:[],
      p_response_length:.5,p_memory_enabled:true,p_retention_days:null};
    const saved=await rpc<Record<string,any>>(db,'morrow_save_companion',settings);
    const companion=saved.companion.id;
    const conversation=(await rpc<Record<string,any>>(db,'morrow_create_conversation',{
      p_owner:'alice',p_companion:companion})).conversation.id;
    const begin=async()=>{
      const request=randomUUID();
      const claim=await rpc<Record<string,any>>(db,'morrow_begin_turn',{
        p_owner:'alice',p_conversation:conversation,p_request:request,p_content:'My sister is Maya.'});
      await rpc(db,'morrow_complete_turn',{
        p_owner:'alice',p_request:request,p_lease:claim.lease,p_content:'What is Maya like?'});
      const job=await rpc<Record<string,any>>(db,'morrow_claim_memory_job',{p_owner:'alice',p_request:request});
      return {request,job};
    };
    const candidates=[{key:'people.maya',category:'people',quote:'My sister is Maya.',confidence:.95,importance:.8}];
    const apply=async(turn:{request:string;job:any})=>rpc<Record<string,any>>(db,'morrow_apply_memory_job',{
      p_owner:'alice',p_request:turn.request,p_lease:turn.job.job.lease,p_candidates:candidates});
    const first=await begin();assert.equal((await apply(first)).saved,1);
    const read=()=>rpc<Record<string,any>>(db,'morrow_list_memories',{p_owner:'alice',p_companion:companion});
    const memory=(await read()).memories[0];
    assert.equal(memory.content,'My sister is Maya.');assert.ok(memory.source_message_id);
    await assert.rejects(rpc(db,'morrow_list_memories',{p_owner:'bob',p_companion:companion}),/not_found/);
    await rpc(db,'morrow_save_memory',{p_owner:'alice',p_companion:companion,p_id:memory.id,
      p_category:'people',p_title:'My sister',p_content:'Maya, my sister and sketching partner.',p_expires_at:null});
    assert.equal((await apply(await begin())).saved,0);
    assert.match((await read()).memories[0].content,/sketching partner/);
    await rpc(db,'morrow_forget_memory',{p_owner:'alice',p_id:memory.id});
    assert.equal((await apply(await begin())).saved,0);assert.equal((await read()).total,0);
    const inFlight=await begin();
    await rpc(db,'morrow_save_companion',{...settings,p_memory_enabled:false});
    assert.equal((await apply(inFlight)).saved,0);
    assert.equal((await rpc<Record<string,any>>(db,'morrow_search_memories',{
      p_owner:'alice',p_companion:companion,p_query:'Maya'})).memories.length,0);
    await rpc(db,'morrow_save_companion',settings);
    const beforeReset=await begin();
    await rpc(db,'morrow_forget_all_memories',{p_owner:'alice',p_companion:companion});
    await assert.rejects(apply(beforeReset),/stale_turn/);
    const manual=await rpc<Record<string,any>>(db,'morrow_save_memory',{
      p_owner:'alice',p_companion:companion,p_id:null,p_category:'preferences',p_title:'Music',
      p_content:'I enjoy jazz.',p_expires_at:new Date(Date.now()+86400000).toISOString()});
    const expiry=manual.memory.expires_at;
    await rpc(db,'morrow_save_companion',{...settings,p_retention_days:30});
    await rpc(db,'morrow_save_companion',settings);
    assert.equal((await read()).memories[0].expires_at,expiry,'explicit expiry survives changes to default retention');
    await db.query("update public.memories set expires_at=now()-interval '1 second' where id=$1",[manual.memory.id]);
    assert.equal((await read()).total,0);
  }finally{await db.close();}
});
