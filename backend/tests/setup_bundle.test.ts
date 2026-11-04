import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {emptyDatabase,rpc} from './database.ts';

test('the delivered setup SQL installs the exact application schema and rejects accidental reinstallation',async()=>{
 const db=await emptyDatabase();try{
  const sql=await readFile(new URL('../../supabase/setup/ai_companion_complete_setup.sql',import.meta.url),'utf8');
  const manifest=JSON.parse(await readFile(new URL('../../supabase/setup/source-manifest.json',import.meta.url),'utf8'));
  assert.equal(createHash('sha256').update(sql).digest('hex'),manifest.bundle_sha256);
  assert.deepEqual(manifest.migrations.map(source=>source.file),(await readdir(new URL('../../supabase/migrations/',import.meta.url))).filter(file=>/^\d+_.+\.sql$/.test(file)).sort(),'Regenerate the SQL bundle after adding migrations');
  for(const source of manifest.migrations){
   const current=(await readFile(new URL(`../../supabase/migrations/${source.file}`,import.meta.url),'utf8')).replaceAll('\r\n','\n');
   assert.equal(createHash('sha256').update(current).digest('hex'),source.sha256,`${source.file} changed; regenerate the delivered bundle`);
  }
  await db.exec(sql);
  await db.exec(await readFile(new URL('../../supabase/setup/verify_installation.sql',import.meta.url),'utf8'));
  const tables=await db.query<{tablename:string;rowsecurity:boolean}>("select tablename,rowsecurity from pg_tables where schemaname='public'");
  assert.equal(tables.rows.length,23);assert.ok(tables.rows.every(t=>t.rowsecurity));
  assert.equal((await db.query<{firebase_project_id:string}>('select firebase_project_id from public.identity_configuration')).rows[0].firebase_project_id,'ai-personal-companion');
  assert.equal((await db.query<{n:number}>('select count(*)::int n from public.profiles')).rows[0].n,0);
  await rpc(db,'morrow_bootstrap',{p_owner:'firebase-test-uid'});
  await rpc(db,'morrow_save_named_profile',{p_owner:'firebase-test-uid',p_username:'marvin',p_preferred_name:'Marvin',p_display_name:null,p_timezone:'Africa/Kampala',p_language:null,p_location:null});
  const {companion}=await rpc<any>(db,'morrow_save_companion',{p_owner:'firebase-test-uid',p_name:'Lumi',p_style:'Playful',p_interests:[],p_response_length:.5,p_memory_enabled:false,p_retention_days:null});
  assert.equal((await rpc<any>(db,'morrow_companion_context',{p_owner:'firebase-test-uid',p_companion:companion.id})).identity.preferred_name,'Marvin');
  await assert.rejects(db.exec(sql),/already exist/);await db.exec('rollback');
  assert.equal((await rpc<any>(db,'morrow_bootstrap',{p_owner:'firebase-test-uid'})).profile.username,'marvin');
 }finally{await db.close();}
});
