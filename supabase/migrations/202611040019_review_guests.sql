-- Explicit, revocable review access; anonymous Firebase identities remain denied.
create table public.review_configuration (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 version uuid not null default gen_random_uuid()
);
insert into public.review_configuration(singleton) values(true);
create table public.review_guest_sessions (
 owner_id text primary key check(owner_id ~ '^review_[0-9a-f-]{36}$'),
 version uuid not null,
 created_at timestamptz not null default now(),
 last_seen_at timestamptz not null default now()
);
create index review_guest_last_seen on public.review_guest_sessions(last_seen_at);
alter table public.review_configuration enable row level security;
alter table public.review_guest_sessions enable row level security;
revoke all on public.review_configuration,public.review_guest_sessions from public,anon,authenticated;
grant all on public.review_configuration,public.review_guest_sessions to service_role;

create function public.morrow_review_status() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('enabled',enabled,'version',version) from public.review_configuration where singleton;
$$;
create function public.morrow_review_begin(p_owner text,p_version uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('ai_companion_review_issuance',0));
 if p_owner is null or p_owner !~ '^review_[0-9a-f-]{36}$' then raise exception 'invalid_input'; end if;
 if not exists(select 1 from public.review_configuration where singleton and enabled and version=p_version)
  then raise exception 'review_access_ended'; end if;
 if (select count(*) from public.review_guest_sessions where created_at>now()-interval '1 hour')>=100
  then raise exception 'rate_limited'; end if;
 insert into public.review_guest_sessions(owner_id,version) values(p_owner,p_version);
 return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_review_guard(p_owner text,p_version uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.review_guest_sessions s join public.review_configuration c on c.singleton
  where c.enabled and c.version=p_version and s.version=c.version and s.owner_id=p_owner
  and not exists(select 1 from public.account_deletions d where d.owner_id=p_owner))
  then raise exception 'review_access_ended'; end if;
 update public.review_guest_sessions set last_seen_at=now() where owner_id=p_owner and last_seen_at<now()-interval '1 hour';
 return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_review_cleanup() returns jsonb
language plpgsql security invoker set search_path='' as $$
declare owner text; queued integer:=0;
begin
 for owner in select s.owner_id from public.review_guest_sessions s cross join public.review_configuration c
  where c.singleton and (not c.enabled or s.version<>c.version or s.last_seen_at<now()-interval '30 days')
  and not exists(select 1 from public.account_deletions d where d.owner_id=s.owner_id)
  order by s.last_seen_at limit 50 loop
   perform public.morrow_request_erasure(owner);queued:=queued+1;
 end loop;
 return jsonb_build_object('queued',queued);
end; $$;

create or replace function public.morrow_authenticated_owner() returns text
language sql stable security definer set search_path='' as $$
select case when (auth.jwt()->>'iss')='https://securetoken.google.com/'||c.firebase_project_id
 and (auth.jwt()->'firebase'->>'tenant') is null
 and coalesce(auth.jwt()->'firebase'->>'sign_in_provider','') not in ('','anonymous')
 and not exists(select 1 from public.account_deletions d where d.owner_id=auth.jwt()->>'sub')
 and (case when auth.jwt()->>'review_guest'='true' or left(auth.jwt()->>'sub',7)='review_' then
  exists(select 1 from public.review_guest_sessions s cross join public.review_configuration r
   where r.singleton and r.enabled and r.version=s.version and s.owner_id=auth.jwt()->>'sub'
   and auth.jwt()->>'review_guest'='true' and auth.jwt()->>'review_version'=r.version::text)
  else true end)
 then auth.jwt()->>'sub' else null end from public.identity_configuration c where c.singleton;
$$;

-- Keep the existing lease/erasure transaction and erase the review registry too.
create or replace function public.morrow_erase_application_data(p_owner text,p_lease uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from public.account_deletions where owner_id=p_owner and lease=p_lease and status='erasing' and lease_until>now() for update;
 if not found then raise exception 'stale_turn'; end if;
 delete from public.profiles where user_id=p_owner;
 delete from public.review_guest_sessions where owner_id=p_owner;
 update public.account_deletions set data_erased=true where owner_id=p_owner;
 return jsonb_build_object('ok',true);
end; $$;
do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in
 ('morrow_review_status','morrow_review_begin','morrow_review_guard','morrow_review_cleanup') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
notify pgrst,'reload schema';
