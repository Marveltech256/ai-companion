-- Read-only checks after running ai_companion_complete_setup.sql.
-- Run in the same Supabase project's SQL Editor.
with expected(name) as (values
 ('profiles'),('companions'),('conversations'),('turn_requests'),('messages'),
 ('memories'),('memory_tombstones'),('memory_jobs'),('interaction_patterns'),
 ('notification_preferences'),('device_tokens'),('scheduled_checkins'),
 ('voice_usage'),('identity_configuration'),('account_deletions'),('consent_events'),
 ('content_reports'),('billing_configuration'),('billing_accounts'),('subscriptions'),('billing_usage'),
 ('review_configuration'),('review_guest_sessions'))
select e.name as application_table,c.oid is not null as exists,
 coalesce(c.relrowsecurity,false) as row_level_security_enabled
from expected e left join pg_class c on c.relname=e.name and c.relnamespace='public'::regnamespace
order by e.name;

-- Must return ai-personal-companion.
select firebase_project_id from public.identity_configuration where singleton;

-- Must include identity, adult age range, automatic timezone, reply preference
-- and once-only introduction/welcome fields (through migration 016).
select column_name,data_type from information_schema.columns
where table_schema='public' and table_name='profiles' and column_name in
 ('user_id','username','preferred_name','age_group','language','timezone','timezone_automatic','reply_mode','introduction_completed_at','welcome_completed_at')
order by ordinal_position;

-- Companion preferences from additive migration 020; existing ownership/RLS is retained.
select column_name,data_type from information_schema.columns
where table_schema='public' and table_name='companions' and column_name in
 ('name','personality_keys','support_preferences','interaction_style','learning_interests','personal_goals','additional_information','preferences_completed_at')
order by ordinal_position;

-- Must include inactivity_days after migration 015.
select column_name,data_type from information_schema.columns where table_schema='public'
 and table_name='notification_preferences' and column_name='inactivity_days';

-- Must show unique_profile_username.
select indexname,indexdef from pg_indexes where schemaname='public' and tablename='profiles';

-- Application write RPCs must be service-only. The two read-policy helpers
-- morrow_authenticated_owner/morrow_visible_conversation are intentionally
-- executable by authenticated, with ownership checks inside them.
select p.proname as function_name,pg_get_function_identity_arguments(p.oid) as arguments,
 has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
 has_function_privilege('service_role',p.oid,'EXECUTE') as service_can_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and left(p.proname,7)='morrow_' order by p.proname,arguments;
