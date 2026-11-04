import {readFile,readdir,mkdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const root=new URL('../',import.meta.url);
const directory=new URL('supabase/migrations/',root);
const files=(await readdir(directory)).filter(f=>/^\d+_.+\.sql$/.test(f)).sort();
const migrations=await Promise.all(files.map(async file=>({file,sql:(await readFile(new URL(file,directory),'utf8')).replaceAll('\r\n','\n')})));
const tables=[...new Set(migrations.flatMap(m=>[...m.sql.matchAll(/create table public\.([a-z_]+)/gi)].map(match=>match[1])))];
const tableList=tables.map(t=>`'${t}'`).join(',');
const header=`-- AI COMPANION: complete setup for an EMPTY application database.
-- Supabase project: rvokidwyzwygpzzkpqck
-- Firebase project: ai-personal-companion
-- Run this entire file ONCE in Supabase Dashboard > SQL Editor > New query.
-- It includes all ${files.length} source migrations; do not also apply them separately.
-- Creates no users, demo rows, external schedules or private credentials.
-- Existing application objects cause a safe stop before any schema changes.
-- Firebase owns accounts; public.profiles.user_id is the verified Firebase UID.

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('ai_companion_empty_database_setup',0));
do $preflight$
declare conflicts text;
begin
 if to_regprocedure('auth.jwt()') is null or not exists(select 1 from pg_roles where rolname='service_role')
  or not exists(select 1 from pg_roles where rolname='anon') or not exists(select 1 from pg_roles where rolname='authenticated') then
  raise exception 'Run this in your Supabase project SQL Editor. Required managed auth roles/functions are missing.';
 end if;
 select string_agg(tablename,', ' order by tablename) into conflicts from pg_tables
  where schemaname='public' and tablename in (${tableList});
 if conflicts is not null or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and left(p.proname,7)='morrow_') then
  raise exception 'Ai Companion application objects already exist. Do not rerun the fresh setup. Inspect existing migrations/tables first. Tables: %',coalesce(conflicts,'existing application functions');
 end if;
end;
$preflight$;
grant usage on schema public to anon,authenticated,service_role;
`;
const sections=migrations.map(m=>`\n-- BEGIN ${m.file}\n${m.sql.trim()}\n-- END ${m.file}\n`);
const footer=`
-- Make the new schema visible through the Data API after commit.
notify pgrst,'reload schema';
commit;

select jsonb_build_object('status','installed','application','Ai Companion',
 'firebase_project',(select firebase_project_id from public.identity_configuration where singleton),
 'application_tables',(select count(*) from pg_tables where schemaname='public' and tablename in (${tableList})),
 'next_step','Configure server secrets and deploy the Edge Functions. Then sign up in the app.') as setup_result;
`;
await mkdir(new URL('supabase/setup/',root),{recursive:true});
const sql=header+sections.join('')+footer;
await writeFile(new URL('supabase/setup/ai_companion_complete_setup.sql',root),sql,'utf8');
await writeFile(new URL('supabase/setup/source-manifest.json',root),JSON.stringify({firebase_project:'ai-personal-companion',supabase_project:'rvokidwyzwygpzzkpqck',tables,migrations:migrations.map(m=>({file:m.file,sha256:createHash('sha256').update(m.sql).digest('hex')})),bundle_sha256:createHash('sha256').update(sql).digest('hex')},null,2)+'\n','utf8');
console.log(JSON.stringify({file:'supabase/setup/ai_companion_complete_setup.sql',migrations:files.length,tables:tables.length,bytes:Buffer.byteLength(sql)}));
