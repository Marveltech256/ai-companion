import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';

export async function emptyDatabase() {
  const db = new PGlite();
  try {
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create function auth.jwt() returns jsonb language sql stable as
    'select coalesce(nullif(current_setting(''request.jwt.claims'',true),''''),''{}'')::jsonb';
    grant usage on schema public,auth to anon,authenticated,service_role;
    grant execute on function auth.jwt() to anon,authenticated,service_role;`);
  return db;
  } catch(error) { await db.close(); throw error; }
}

export async function database() {
  const db=await emptyDatabase();
  try {
  const folder = new URL('../../supabase/migrations/', import.meta.url);
  for (const file of (await readdir(folder)).filter(f=>f.endsWith('.sql')).sort()) {
    await db.exec(await readFile(new URL(file,folder),'utf8'));
  }
  await db.exec("update public.identity_configuration set firebase_project_id='morrow'");
  return db;
  } catch(error) { await db.close(); throw error; }
}

export async function asService<T>(db: PGlite, fn:()=>Promise<T>) {
  await db.exec('set role service_role');
  try { return await fn(); } finally { await db.exec('reset role'); }
}

export async function rpc<T=Record<string,unknown>>(db:PGlite,name:string,args:Record<string,unknown>):Promise<T> {
  const keys=Object.keys(args);
  return asService(db,async()=>{
    const result=await db.query<{value:T}>(`select public.${name}(${keys.map((k,i)=>`${k} => $${i+1}`).join(',')}) as value`,Object.values(args));
    return result.rows[0].value;
  });
}
