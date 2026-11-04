import { test } from 'node:test';
import assert from 'node:assert/strict';
import { database, rpc } from './database.ts';

test('companions persist, remain unique, and are isolated by RLS', async()=>{
  const db=await database();
  try {
    const save=(owner:string,name:string)=>rpc<Record<string,any>>(db,'morrow_save_companion',{
      p_owner:owner,p_name:name,p_style:'Gentle & warm',p_interests:['Music'],
      p_response_length:.5,p_memory_enabled:true,p_retention_days:null});
    await rpc(db,'morrow_bootstrap',{p_owner:'alice'});
    await rpc(db,'morrow_bootstrap',{p_owner:'bob'});
    const first=await save('alice','Lumi');
    const second=await save('alice','Nova');
    assert.equal(first.companion.id,second.companion.id);
    await save('bob','Other');
    const restored=await rpc<Record<string,any>>(db,'morrow_bootstrap',{p_owner:'alice'});
    assert.equal(restored.companion.name,'Nova');
    await db.exec(`set role authenticated; set request.jwt.claims='{"sub":"alice","iss":"https://securetoken.google.com/morrow","firebase":{"sign_in_provider":"password"}}'`);
    assert.equal((await db.query('select * from public.companions')).rows.length,1);
    await assert.rejects(db.query('select public.morrow_bootstrap($1)',['bob']),/permission denied/);
    await assert.rejects(db.query("update public.companions set name='Hacked'"),/permission denied/);
    await db.exec('reset role');
  } finally { await db.close(); }
});
