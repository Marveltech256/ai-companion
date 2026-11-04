-- Optional deployment preparation; NOT part of the application schema bundle.
-- This preparation creates both jobs INACTIVE. Live status is tracked separately
-- in docs/remaining-phases.md; never rerun against existing jobs.
-- Before running: enable pg_cron/pg_net and securely provision the SAME random
-- value as Edge SCHEDULER_SECRET and Vault ai_companion_scheduler_secret.
-- Never put the value in this file, Flutter, a public key, or chat.
-- Activate check-ins only after paid provider setup and a real device test.
begin;
do $$ begin
 if not exists(select 1 from pg_extension where extname='pg_cron')
  or not exists(select 1 from pg_extension where extname='pg_net') then
  raise exception 'Enable Supabase Cron and pg_net before preparing scheduler jobs.';
 end if;
 if not exists(select 1 from vault.secrets where name='ai_companion_scheduler_secret') then
  raise exception 'Securely provision the shared scheduler secret in Edge secrets and Vault first.';
 end if;
 if exists(select 1 from cron.job where jobname in ('ai-companion-checkins','ai-companion-privacy')) then
  raise exception 'An application scheduler job already exists. Inspect it instead of overwriting it.';
 end if;
end; $$;

select cron.schedule('ai-companion-checkins','*/5 * * * *',$job$
 select net.http_post(
  url:='https://rvokidwyzwygpzzkpqck.supabase.co/functions/v1/checkin-dispatch',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||
   (select decrypted_secret from vault.decrypted_secrets where name='ai_companion_scheduler_secret')),
  body:='{}'::jsonb,timeout_milliseconds:=120000);
$job$);
select cron.schedule('ai-companion-privacy','15 2 * * *',$job$
 select net.http_post(
  url:='https://rvokidwyzwygpzzkpqck.supabase.co/functions/v1/privacy-maintenance',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||
   (select decrypted_secret from vault.decrypted_secrets where name='ai_companion_scheduler_secret')),
  body:='{}'::jsonb,timeout_milliseconds:=120000);
$job$);
select cron.alter_job(jobid,active:=false) from cron.job
 where jobname in ('ai-companion-checkins','ai-companion-privacy');
commit;

select jobname,schedule,active from cron.job
 where jobname in ('ai-companion-checkins','ai-companion-privacy');
-- Later, after readiness checks, use cron.alter_job(jobid,active:=true).
-- Cron HTTP acceptance is not proof that a device received a notification.
