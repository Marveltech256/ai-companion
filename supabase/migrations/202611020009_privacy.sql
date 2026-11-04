-- Local candidate. Inspect target schema and Firebase project before applying.
create table public.identity_configuration (
  singleton boolean primary key default true check(singleton),
  firebase_project_id text not null check(length(firebase_project_id) between 1 and 100)
);
insert into public.identity_configuration(firebase_project_id) values('ai-personal-companion');
revoke all on public.identity_configuration from public,anon,authenticated;
grant all on public.identity_configuration to service_role;
alter table public.identity_configuration enable row level security;
create table public.account_deletions (
  owner_id text primary key,
  status text not null default 'requested' check(status in ('requested','erasing','failed','complete')),
  data_erased boolean not null default false,
  lease uuid,lease_until timestamptz,attempts integer not null default 0,
  requested_at timestamptz not null default now(),completed_at timestamptz
);
alter table public.account_deletions enable row level security;
revoke all on public.account_deletions from public,anon,authenticated;
grant all on public.account_deletions to service_role;
alter table public.companions add column conversation_retention_days integer
  check(conversation_retention_days between 1 and 3650);
create table public.consent_events (
  id uuid primary key default gen_random_uuid(),
  owner_id text not null references public.profiles(user_id) on delete cascade,
  kind text not null check(kind in ('memory','learning','voice','notifications')),
  enabled boolean not null,created_at timestamptz not null default now()
);
alter table public.consent_events enable row level security;
revoke all on public.consent_events from public,anon,authenticated;
grant select on public.consent_events to authenticated;
grant all on public.consent_events to service_role;

create function public.morrow_authenticated_owner() returns text
language sql stable security definer set search_path='' as $$
select case when (auth.jwt()->>'iss')='https://securetoken.google.com/'||c.firebase_project_id
 and (auth.jwt()->'firebase'->>'tenant') is null
 and not exists(select 1 from public.account_deletions d where d.owner_id=auth.jwt()->>'sub')
 then auth.jwt()->>'sub' else null end from public.identity_configuration c where c.singleton;
$$;
create function public.morrow_visible_conversation(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
select exists(select 1 from public.conversations v join public.companions c on c.id=v.companion_id and c.owner_id=v.owner_id
 where v.id=p_id and v.owner_id=public.morrow_authenticated_owner() and
 (c.conversation_retention_days is null or v.updated_at>now()-make_interval(days=>c.conversation_retention_days)));
$$;
revoke all on function public.morrow_authenticated_owner(),public.morrow_visible_conversation(uuid) from public,anon;
grant execute on function public.morrow_authenticated_owner(),public.morrow_visible_conversation(uuid) to authenticated,service_role;
do $$ declare t text; policy record; condition text; begin
  foreach t in array array['profiles','companions','conversations','messages','memories',
    'interaction_patterns','notification_preferences','consent_events'] loop
    for policy in select polname from pg_policy where polrelid=format('public.%I',t)::regclass loop
      execute format('drop policy %I on public.%I',policy.polname,t);
    end loop;
    condition=case when t='profiles' then 'user_id' else 'owner_id' end||'=(select public.morrow_authenticated_owner())';
    if t='conversations' then condition=condition||' and public.morrow_visible_conversation(id)'; end if;
    if t='messages' then condition=condition||' and public.morrow_visible_conversation(conversation_id)'; end if;
    if t='memories' then condition=condition||' and (expires_at is null or expires_at>now())'; end if;
    execute format('create policy exact_owner_read on public.%I for select to authenticated using (%s)',t,condition);
  end loop;
end; $$;

create function public.morrow_reject_deleted_insert() returns trigger
language plpgsql security invoker set search_path='' as $$
declare owner text;
begin
  owner=case when tg_table_name='profiles' then to_jsonb(new)->>'user_id' else to_jsonb(new)->>'owner_id' end;
  if tg_table_name='profiles' then perform pg_advisory_xact_lock(hashtextextended(owner,0)); end if;
  if exists(select 1 from public.account_deletions where owner_id=owner) then raise exception 'account_deleted'; end if;
  return new;
end; $$;
do $$ declare t text; begin
 foreach t in array array['profiles','companions','conversations','messages','turn_requests','memories',
  'memory_jobs','memory_tombstones','interaction_patterns','notification_preferences','device_tokens',
  'scheduled_checkins','voice_usage','consent_events'] loop
  execute format('create trigger reject_deleted_insert before insert on public.%I for each row execute function public.morrow_reject_deleted_insert()',t);
 end loop;
end; $$;
create function public.morrow_audit_consent() returns trigger
language plpgsql security invoker set search_path='' as $$
declare kind text; current_value boolean; previous_value boolean; begin
 if tg_table_name='companions' then
  foreach kind in array array['memory','learning','voice'] loop
   current_value=(to_jsonb(new)->>(kind||'_enabled'))::boolean;
   previous_value=case when tg_op='INSERT' then null else (to_jsonb(old)->>(kind||'_enabled'))::boolean end;
   if current_value is distinct from previous_value then insert into public.consent_events(owner_id,kind,enabled)
    values(new.owner_id,kind,current_value); end if;
  end loop;
 else
  current_value=new.checkins_enabled or new.suggestions_enabled or new.birthdays_enabled;
  previous_value=case when tg_op='INSERT' then null else old.checkins_enabled or old.suggestions_enabled or old.birthdays_enabled end;
  if current_value is distinct from previous_value then insert into public.consent_events(owner_id,kind,enabled)
   values(new.owner_id,'notifications',current_value); end if;
 end if;
 return new;
end; $$;
create trigger audit_companion_consent after insert or update on public.companions for each row execute function public.morrow_audit_consent();
create trigger audit_notification_consent after insert or update on public.notification_preferences for each row execute function public.morrow_audit_consent();

create function public.morrow_account_status(p_owner text) returns jsonb
language sql security invoker set search_path='' as $$
select coalesce((select jsonb_build_object('blocked',true,'status',status,'data_erased',data_erased)
 from public.account_deletions where owner_id=p_owner),jsonb_build_object('blocked',false,'status','active'));
$$;
create function public.morrow_guard_account(p_owner text,p_project text) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.identity_configuration where firebase_project_id=p_project)
  then raise exception 'identity_configuration_mismatch'; end if;
 if exists(select 1 from public.account_deletions where owner_id=p_owner) then raise exception 'account_deleted'; end if;
 delete from public.conversations v using public.companions c where v.owner_id=p_owner and c.owner_id=p_owner
  and c.id=v.companion_id and c.conversation_retention_days is not null
  and v.updated_at<=now()-make_interval(days=>c.conversation_retention_days);
 delete from public.memories where owner_id=p_owner and expires_at<=now();
 return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_set_conversation_retention(p_owner text,p_companion uuid,p_days integer)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; begin
 update public.companions set conversation_retention_days=p_days,updated_at=now()
  where owner_id=p_owner and id=p_companion returning to_jsonb(companions.*) into result;
 if not found then raise exception 'not_found'; end if;
 return jsonb_build_object('companion',result);
end; $$;

create function public.morrow_export_page(p_owner text,p_section text,p_after text default '')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tab text; own text='owner_id'; key text; rows jsonb; output jsonb; count integer; next_cursor text; begin
 if exists(select 1 from public.account_deletions where owner_id=p_owner) then raise exception 'account_deleted'; end if;
 tab=case p_section when 'profile' then 'profiles' when 'companion' then 'companions'
  when 'conversations' then 'conversations' when 'messages' then 'messages' when 'memories' then 'memories'
  when 'patterns' then 'interaction_patterns' when 'notifications' then 'notification_preferences'
  when 'checkins' then 'scheduled_checkins' when 'consents' then 'consent_events' else null end;
 if tab is null or length(p_after)>200 then raise exception 'invalid_input'; end if;
 if tab='profiles' then own='user_id';key='user_id';
 elsif tab='interaction_patterns' then key='companion_id::text';
 elsif tab='notification_preferences' then key='owner_id';
 elsif tab='messages' then key='lpad(seq::text,20,''0'')';
 else key='id::text'; end if;
 execute format('select coalesce(jsonb_agg(value),''[]''::jsonb) from (select to_jsonb(t)||jsonb_build_object(''_cursor'',%s) as value from public.%I t where %I=$1 and %s>$2 %s order by %s limit 201) page',
  key,tab,own,key,case when tab='memories' then 'and (expires_at is null or expires_at>now())' else '' end,key)
  into rows using p_owner,p_after;
 count=jsonb_array_length(rows);
 select coalesce(jsonb_agg(value-'_cursor'),'[]'::jsonb) into output
  from jsonb_array_elements(rows) with ordinality as e(value,n) where n<=200;
 if count>200 then next_cursor=rows->199->>'_cursor'; end if;
 -- Internal leases and delivery identifiers are never part of the export.
 if tab='conversations' then select coalesce(jsonb_agg(value-'active_request_id'-'active_until'),'[]') into output from jsonb_array_elements(output); end if;
 if tab='scheduled_checkins' then select coalesce(jsonb_agg(value-'lease'-'lease_until'),'[]') into output from jsonb_array_elements(output); end if;
 if tab='memories' then select coalesce(jsonb_agg(value-'search_vector'),'[]') into output from jsonb_array_elements(output); end if;
 return jsonb_build_object('section',p_section,'rows',output,'next_cursor',next_cursor);
end; $$;

create function public.morrow_request_erasure(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 update public.notification_preferences set checkins_enabled=false,suggestions_enabled=false,
  birthdays_enabled=false,revision=revision+1,updated_at=now() where owner_id=p_owner;
 delete from public.device_tokens where owner_id=p_owner;
 insert into public.account_deletions(owner_id) values(p_owner) on conflict do nothing;
 return public.morrow_account_status(p_owner);
end; $$;
create function public.morrow_claim_erasure(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare job public.account_deletions; begin
 select * into job from public.account_deletions where owner_id=p_owner for update;
 if not found or job.status='complete' or job.attempts>=10 or
  (job.status='erasing' and job.lease_until>now()) then return jsonb_build_object('job',null); end if;
 update public.account_deletions set status='erasing',lease=gen_random_uuid(),lease_until=now()+interval '2 minutes',
  attempts=attempts+1 where owner_id=p_owner returning * into job;
 return jsonb_build_object('job',to_jsonb(job));
end; $$;
create function public.morrow_erase_application_data(p_owner text,p_lease uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from public.account_deletions where owner_id=p_owner and lease=p_lease and status='erasing' and lease_until>now() for update;
 if not found then raise exception 'stale_turn'; end if;
 delete from public.profiles where user_id=p_owner;
 update public.account_deletions set data_erased=true where owner_id=p_owner;
 return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_finish_erasure(p_owner text,p_lease uuid,p_complete boolean) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 update public.account_deletions set status=case when p_complete and data_erased then 'complete' else 'failed' end,
  completed_at=case when p_complete and data_erased then now() else null end,lease_until=null
  where owner_id=p_owner and lease=p_lease and status='erasing';
 return public.morrow_account_status(p_owner);
end; $$;
create function public.morrow_pending_erasures() returns jsonb
language sql security invoker set search_path='' as $$
select jsonb_build_object('owners',coalesce(jsonb_agg(owner_id),'[]')) from (
 select owner_id from public.account_deletions where attempts<10 and
 (status in ('requested','failed') or (status='erasing' and lease_until<now())) order by requested_at limit 20) pending;
$$;
create function public.morrow_privacy_cleanup() returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 delete from public.conversations v using public.companions c where c.id=v.companion_id and c.owner_id=v.owner_id
  and c.conversation_retention_days is not null and v.updated_at<=now()-make_interval(days=>c.conversation_retention_days);
 delete from public.memories where expires_at<=now();
 delete from public.voice_usage where created_at<now()-interval '1 day';
 delete from public.device_tokens where updated_at<now()-interval '90 days';
 delete from public.scheduled_checkins where created_at<now()-interval '30 days';
 delete from public.consent_events where created_at<now()-interval '365 days';
 return jsonb_build_object('ok',true);
end; $$;
do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
  'morrow_reject_deleted_insert','morrow_audit_consent','morrow_account_status','morrow_guard_account',
  'morrow_set_conversation_retention','morrow_export_page','morrow_request_erasure','morrow_claim_erasure',
  'morrow_erase_application_data','morrow_finish_erasure','morrow_pending_erasures','morrow_privacy_cleanup') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
