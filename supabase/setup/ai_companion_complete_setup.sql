-- AI COMPANION: complete setup for an EMPTY application database.
-- Supabase project: rvokidwyzwygpzzkpqck
-- Firebase project: ai-personal-companion
-- Run this entire file ONCE in Supabase Dashboard > SQL Editor > New query.
-- It includes all 20 source migrations; do not also apply them separately.
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
  where schemaname='public' and tablename in ('profiles','companions','conversations','turn_requests','messages','memories','memory_tombstones','memory_jobs','interaction_patterns','notification_preferences','device_tokens','scheduled_checkins','voice_usage','identity_configuration','account_deletions','consent_events','content_reports','billing_configuration','billing_accounts','subscriptions','billing_usage','review_configuration','review_guest_sessions');
 if conflicts is not null or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and left(p.proname,7)='morrow_') then
  raise exception 'Ai Companion application objects already exist. Do not rerun the fresh setup. Inspect existing migrations/tables first. Tables: %',coalesce(conflicts,'existing application functions');
 end if;
end;
$preflight$;
grant usage on schema public to anon,authenticated,service_role;

-- BEGIN 202611020001_foundation.sql
-- LOCAL CANDIDATE: inspect the target project's schema before applying.
-- Firebase owns identity, so a Firebase UID is TEXT, not auth.users.id/UUID.
create table public.profiles (
  user_id text primary key check (length(user_id) between 1 and 128),
  display_name text check (length(display_name) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy own_profile_read on public.profiles for select to authenticated
  using (user_id = (select auth.jwt()->>'sub')
    and (select auth.jwt()->>'iss') like 'https://securetoken.google.com/%');
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant all on public.profiles to service_role;

create function public.morrow_bootstrap(p_owner text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb;
begin
  insert into public.profiles(user_id) values(p_owner) on conflict do nothing;
  select to_jsonb(p) into result from public.profiles p where p.user_id = p_owner;
  return jsonb_build_object('profile', result);
end;
$$;
revoke all on function public.morrow_bootstrap(text) from public, anon, authenticated;
grant execute on function public.morrow_bootstrap(text) to service_role;
-- END 202611020001_foundation.sql

-- BEGIN 202611020002_companions.sql
create table public.companions (
  id uuid primary key default gen_random_uuid(),
  owner_id text not null unique references public.profiles(user_id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 24),
  communication_style text not null check (communication_style in ('Gentle & warm','Playful','Reflective')),
  interests text[] not null default '{}' check (cardinality(interests) <= 5
    and interests <@ array['Art & making','Music','Little adventures','Books','Cooking']::text[]),
  response_length real not null default 0.5 check (response_length between 0 and 1),
  memory_enabled boolean not null default false,
  retention_days integer check (retention_days between 1 and 3650),
  consent_version bigint not null default 1,
  memory_reset_at timestamptz not null default 'epoch',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, id)
);
alter table public.companions enable row level security;
create policy own_companion_read on public.companions for select to authenticated
  using (owner_id = (select auth.jwt()->>'sub')
    and (select auth.jwt()->>'iss') like 'https://securetoken.google.com/%');
revoke all on public.companions from anon, authenticated;
grant select on public.companions to authenticated;
grant all on public.companions to service_role;

create or replace function public.morrow_bootstrap(p_owner text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb; companion jsonb;
begin
  insert into public.profiles(user_id) values(p_owner) on conflict do nothing;
  select to_jsonb(p) into result from public.profiles p where p.user_id=p_owner;
  select to_jsonb(c) into companion from public.companions c where c.owner_id=p_owner;
  return jsonb_build_object('profile', result, 'companion', companion);
end;
$$;

create function public.morrow_save_profile(p_owner text, p_display_name text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb;
begin
  update public.profiles set display_name=nullif(btrim(p_display_name),''), updated_at=now()
  where user_id=p_owner returning to_jsonb(profiles.*) into result;
  if result is null then raise exception 'not_found'; end if;
  return jsonb_build_object('profile', result);
end;
$$;

create function public.morrow_save_companion(p_owner text, p_name text,
  p_style text, p_interests text[], p_response_length real,
  p_memory_enabled boolean, p_retention_days integer)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb;
begin
  insert into public.companions(owner_id,name,communication_style,interests,
    response_length,memory_enabled,retention_days)
  values(p_owner,btrim(p_name),p_style,p_interests,p_response_length,p_memory_enabled,p_retention_days)
  on conflict(owner_id) do update set name=excluded.name,
    communication_style=excluded.communication_style, interests=excluded.interests,
    response_length=excluded.response_length, memory_enabled=excluded.memory_enabled,
    retention_days=excluded.retention_days, updated_at=now(),
    consent_version=case when companions.memory_enabled is distinct from excluded.memory_enabled
      or companions.retention_days is distinct from excluded.retention_days
      then companions.consent_version+1 else companions.consent_version end
  returning to_jsonb(companions.*) into result;
  return jsonb_build_object('companion',result);
end;
$$;
revoke all on function public.morrow_save_profile(text,text) from public,anon,authenticated;
revoke all on function public.morrow_save_companion(text,text,text,text[],real,boolean,integer) from public,anon,authenticated;
grant execute on function public.morrow_save_profile(text,text) to service_role;
grant execute on function public.morrow_save_companion(text,text,text,text[],real,boolean,integer) to service_role;
-- END 202611020002_companions.sql

-- BEGIN 202611020003_conversations.sql
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  owner_id text not null,
  companion_id uuid not null,
  title text not null default 'A little space for you.' check(length(title) between 1 and 100),
  active_request_id uuid,
  active_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,companion_id) references public.companions(owner_id,id) on delete cascade
);
create table public.turn_requests (
  id uuid primary key,
  owner_id text not null,
  conversation_id uuid not null,
  status text not null check(status in ('running','completed','failed')),
  lease uuid not null default gen_random_uuid(),
  lease_until timestamptz not null,
  consent_version bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,conversation_id) references public.conversations(owner_id,id) on delete cascade
);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  seq bigint generated always as identity unique,
  owner_id text not null,
  conversation_id uuid not null,
  request_id uuid not null,
  role text not null check(role in ('user','assistant')),
  content text not null check(length(content)<=12000),
  status text not null check(status in ('pending','completed','failed')),
  created_at timestamptz not null default now(),
  unique(owner_id,id),
  unique(request_id,role),
  foreign key(owner_id,conversation_id) references public.conversations(owner_id,id) on delete cascade,
  foreign key(owner_id,request_id) references public.turn_requests(owner_id,id) on delete cascade
);
create index messages_history on public.messages(owner_id,conversation_id,seq desc);
create index messages_rate on public.messages(owner_id,created_at desc) where role='user';
create index conversation_recent on public.conversations(owner_id,updated_at desc);

alter table public.conversations enable row level security;
alter table public.turn_requests enable row level security;
alter table public.messages enable row level security;
create policy own_conversations_read on public.conversations for select to authenticated
  using(owner_id=(select auth.jwt()->>'sub') and (select auth.jwt()->>'iss') like 'https://securetoken.google.com/%');
create policy own_messages_read on public.messages for select to authenticated
  using(owner_id=(select auth.jwt()->>'sub') and (select auth.jwt()->>'iss') like 'https://securetoken.google.com/%');
-- Requests and leases are server-only; no direct client policy is granted.
revoke all on public.conversations,public.turn_requests,public.messages from anon,authenticated;
grant select on public.conversations,public.messages to authenticated;
grant all on public.conversations,public.turn_requests,public.messages to service_role;
grant usage,select on sequence public.messages_seq_seq to service_role;

create function public.morrow_create_conversation(p_owner text,p_companion uuid,p_title text default null,p_id uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
  if not exists(select 1 from public.companions where owner_id=p_owner and id=p_companion)
    then raise exception 'not_found'; end if;
  p_id=coalesce(p_id,gen_random_uuid());
  insert into public.conversations(id,owner_id,companion_id,title)
    values(p_id,p_owner,p_companion,coalesce(nullif(btrim(p_title),''),'A little space for you.'))
    on conflict(id) do nothing;
  select to_jsonb(v) into result from public.conversations v
    where id=p_id and owner_id=p_owner and companion_id=p_companion;
  if result is null then raise exception 'not_found'; end if;
  return jsonb_build_object('conversation',result);
end; $$;

create function public.morrow_list_conversations(p_owner text)
returns jsonb language sql security invoker set search_path='' as $$
  select jsonb_build_object('conversations',coalesce(jsonb_agg(to_jsonb(c) order by updated_at desc),'[]'::jsonb))
  from(select * from public.conversations where owner_id=p_owner order by updated_at desc limit 40)c;
$$;

create function public.morrow_messages(p_owner text,p_conversation uuid,p_before bigint default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
  if not exists(select 1 from public.conversations where owner_id=p_owner and id=p_conversation)
    then raise exception 'not_found'; end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by seq),'[]'::jsonb) into result from (
    select m.id,m.seq,m.request_id,m.role,m.content,m.created_at,
      case when m.status='pending' and r.lease_until<now() then 'failed' else m.status end as status
    from public.messages m join public.turn_requests r on r.id=m.request_id
    where m.owner_id=p_owner and m.conversation_id=p_conversation and (p_before is null or m.seq<p_before)
    order by m.seq desc limit 50)m;
  return jsonb_build_object('messages',result);
end; $$;

create function public.morrow_rename_conversation(p_owner text,p_conversation uuid,p_title text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  update public.conversations set title=btrim(p_title),updated_at=now()
    where id=p_conversation and owner_id=p_owner;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_delete_conversation(p_owner text,p_conversation uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  delete from public.conversations where id=p_conversation and owner_id=p_owner;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_begin_turn(p_owner text,p_conversation uuid,p_request uuid,p_content text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.conversations; r public.turn_requests; companion public.companions;
  result jsonb; history jsonb; previous text;
begin
  if length(btrim(p_content)) not between 1 and 12000 then raise exception 'invalid_input'; end if;
  select * into c from public.conversations where id=p_conversation and owner_id=p_owner for update;
  if not found then raise exception 'not_found'; end if;
  select * into companion from public.companions where id=c.companion_id and owner_id=p_owner;
  select * into r from public.turn_requests where id=p_request;
  if found then
    if r.owner_id<>p_owner or r.conversation_id<>p_conversation then raise exception 'request_conflict'; end if;
    select content into previous from public.messages where request_id=p_request and role='user';
    if previous is distinct from p_content then raise exception 'request_conflict'; end if;
    if r.status='completed' then
      select content into previous from public.messages where request_id=p_request and role='assistant';
      return jsonb_build_object('status','completed','text',previous,'request_id',p_request);
    end if;
    if r.status='running' and r.lease_until>now() then raise exception 'turn_busy'; end if;
  end if;
  if c.active_request_id is not null and c.active_request_id<>p_request and c.active_until>now()
    then raise exception 'turn_busy'; end if;
  -- A transaction-level owner lock makes the per-minute limit atomic across conversations.
  perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
  if r.id is null and (select count(*) from public.messages
    where owner_id=p_owner and role='user' and created_at>now()-interval '1 minute')>=10
    then raise exception 'rate_limited'; end if;
  insert into public.turn_requests(id,owner_id,conversation_id,status,lease_until,consent_version)
    values(p_request,p_owner,p_conversation,'running',now()+interval '120 seconds',companion.consent_version)
    on conflict(id) do update set status='running',lease=gen_random_uuid(),
      lease_until=now()+interval '120 seconds',consent_version=companion.consent_version,updated_at=now()
    returning * into r;
  insert into public.messages(owner_id,conversation_id,request_id,role,content,status)
    values(p_owner,p_conversation,p_request,'user',p_content,'completed') on conflict(request_id,role) do nothing;
  insert into public.messages(owner_id,conversation_id,request_id,role,content,status)
    values(p_owner,p_conversation,p_request,'assistant','','pending')
    on conflict(request_id,role) do update set status='pending',content='';
  update public.conversations set active_request_id=p_request,active_until=r.lease_until,
    title=case when title='A little space for you.' then left(p_content,80) else title end,
    updated_at=now() where id=p_conversation;
  select coalesce(jsonb_agg(to_jsonb(m) order by seq),'[]'::jsonb) into history from (
    select seq,role,content from public.messages where owner_id=p_owner
      and conversation_id=p_conversation and status='completed' order by seq desc limit 18)m;
  return jsonb_build_object('status','running','lease',r.lease,'companion',to_jsonb(companion),
    'history',history,'request_id',p_request,'consent_version',r.consent_version);
end; $$;

create function public.morrow_complete_turn(p_owner text,p_request uuid,p_lease uuid,p_content text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.turn_requests;
begin
  if length(btrim(p_content)) not between 1 and 12000 then raise exception 'invalid_input'; end if;
  -- Match begin_turn's lock order when a stale request is retried concurrently.
  perform 1 from public.conversations where owner_id=p_owner and id=(
    select conversation_id from public.turn_requests where id=p_request and owner_id=p_owner)
    for update;
  select * into r from public.turn_requests where id=p_request and owner_id=p_owner for update;
  if not found or r.status<>'running' or r.lease<>p_lease or r.lease_until<now()
    then raise exception 'stale_turn'; end if;
  update public.messages set content=p_content,status='completed'
    where owner_id=p_owner and request_id=p_request and role='assistant';
  update public.turn_requests set status='completed',updated_at=now() where id=p_request;
  update public.conversations set active_request_id=null,active_until=null,updated_at=now()
    where id=r.conversation_id and owner_id=p_owner and active_request_id=p_request;
  return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_fail_turn(p_owner text,p_request uuid,p_lease uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.turn_requests;
begin
  perform 1 from public.conversations where owner_id=p_owner and id=(
    select conversation_id from public.turn_requests where id=p_request and owner_id=p_owner)
    for update;
  update public.turn_requests set status='failed',updated_at=now()
    where id=p_request and owner_id=p_owner and lease=p_lease and status='running' returning * into r;
  if found then
    update public.messages set status='failed' where owner_id=p_owner and request_id=p_request and role='assistant';
    update public.conversations set active_request_id=null,active_until=null
      where id=r.conversation_id and owner_id=p_owner and active_request_id=p_request;
  end if;
  return jsonb_build_object('ok',true);
end; $$;

revoke all on function public.morrow_create_conversation(text,uuid,text,uuid),
  public.morrow_list_conversations(text),public.morrow_messages(text,uuid,bigint),
  public.morrow_rename_conversation(text,uuid,text),public.morrow_delete_conversation(text,uuid),
  public.morrow_begin_turn(text,uuid,uuid,text),public.morrow_complete_turn(text,uuid,uuid,text),
  public.morrow_fail_turn(text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.morrow_create_conversation(text,uuid,text,uuid),
  public.morrow_list_conversations(text),public.morrow_messages(text,uuid,bigint),
  public.morrow_rename_conversation(text,uuid,text),public.morrow_delete_conversation(text,uuid),
  public.morrow_begin_turn(text,uuid,uuid,text),public.morrow_complete_turn(text,uuid,uuid,text),
  public.morrow_fail_turn(text,uuid,uuid) to service_role;
-- END 202611020003_conversations.sql

-- BEGIN 202611020004_memories.sql
create table public.memories (
  id uuid primary key default gen_random_uuid(),owner_id text not null,companion_id uuid not null,
  memory_key text not null check(memory_key ~ '^[a-z0-9_.:-]{1,120}$'),
  category text not null check(category in ('personal_information','preferences','people','experiences',
    'important_dates','goals','discussions','communication_preferences')),
  title text not null check(length(title) between 1 and 100),
  content text not null check(length(content) between 1 and 2000),
  source_quote text check(length(source_quote)<=2000),source_message_id uuid,
  confidence real not null default 1 check(confidence between 0 and 1),
  importance real not null default 0.5 check(importance between 0 and 1),
  user_edited boolean not null default false,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  user_expires_at timestamptz,expires_at timestamptz,
  search_vector tsvector generated always as (to_tsvector('simple',title||' '||content)) stored,
  unique(owner_id,companion_id,memory_key),
  foreign key(owner_id,companion_id) references public.companions(owner_id,id) on delete cascade,
  foreign key(owner_id,source_message_id) references public.messages(owner_id,id) on delete set null (source_message_id)
);
create index memory_search on public.memories using gin(search_vector);
create index memory_owner on public.memories(owner_id,companion_id,updated_at desc);
create table public.memory_tombstones (
  owner_id text not null,companion_id uuid not null,memory_key text not null,
  created_at timestamptz not null default now(),primary key(owner_id,companion_id,memory_key),
  foreign key(owner_id,companion_id) references public.companions(owner_id,id) on delete cascade
);
create table public.memory_jobs (
  request_id uuid primary key,owner_id text not null,companion_id uuid not null,
  consent_version bigint not null,
  status text not null default 'pending' check(status in ('pending','running','completed','suppressed','failed')),
  lease uuid,lease_until timestamptz,attempts integer not null default 0,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  foreign key(owner_id,request_id) references public.turn_requests(owner_id,id) on delete cascade,
  foreign key(owner_id,companion_id) references public.companions(owner_id,id) on delete cascade
);
alter table public.memories enable row level security;
alter table public.memory_tombstones enable row level security;
alter table public.memory_jobs enable row level security;
create policy own_memories_read on public.memories for select to authenticated
  using(owner_id=(select auth.jwt()->>'sub') and (expires_at is null or expires_at>now())
    and (select auth.jwt()->>'iss') like 'https://securetoken.google.com/%');
revoke all on public.memories,public.memory_tombstones,public.memory_jobs from anon,authenticated;
grant select on public.memories to authenticated;
grant all on public.memories,public.memory_tombstones,public.memory_jobs to service_role;

create function public.morrow_enqueue_memory() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  insert into public.memory_jobs(request_id,owner_id,companion_id,consent_version)
    select new.id,new.owner_id,c.id,new.consent_version from public.conversations v
      join public.companions c on c.id=v.companion_id and c.owner_id=new.owner_id
    where v.id=new.conversation_id and c.memory_enabled and c.consent_version=new.consent_version
    on conflict do nothing;
  return new;
end; $$;
create trigger enqueue_memory after update of status on public.turn_requests for each row
  when(new.status='completed' and old.status is distinct from 'completed')
  execute function public.morrow_enqueue_memory();

create function public.morrow_claim_memory_job(p_owner text,p_request uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.memory_jobs;c public.companions;m public.messages;
begin
  select * into j from public.memory_jobs where owner_id=p_owner and request_id=p_request for update;
  if not found or j.status in ('completed','suppressed') or j.attempts>=5
    or (j.status='running' and j.lease_until>now()) then return jsonb_build_object('job',null); end if;
  select * into c from public.companions where id=j.companion_id and owner_id=p_owner;
  select * into m from public.messages where owner_id=p_owner and request_id=p_request and role='user';
  if not c.memory_enabled or c.consent_version<>j.consent_version or m.created_at<=c.memory_reset_at then
    update public.memory_jobs set status='suppressed',updated_at=now() where request_id=p_request;
    return jsonb_build_object('job',null);
  end if;
  update public.memory_jobs set status='running',attempts=attempts+1,
    lease=gen_random_uuid(),lease_until=now()+interval '60 seconds',updated_at=now()
    where request_id=p_request returning * into j;
  return jsonb_build_object('job',to_jsonb(j),'source',jsonb_build_object('id',m.id,'content',m.content));
end; $$;

create function public.morrow_apply_memory_job(p_owner text,p_request uuid,p_lease uuid,p_candidates jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.memory_jobs;c public.companions;m public.messages;candidate jsonb;
  fact_key text;quote text;category text;total integer=0;
begin
  -- Match the companion/settings lock before committing any extracted facts.
  select comp.* into c from public.companions comp join public.memory_jobs job on job.companion_id=comp.id
    where job.request_id=p_request and job.owner_id=p_owner and comp.owner_id=p_owner for update of comp;
  select * into j from public.memory_jobs where request_id=p_request and owner_id=p_owner for update;
  if not found or j.status<>'running' or j.lease<>p_lease or j.lease_until<now() then raise exception 'stale_turn'; end if;
  select * into m from public.messages where owner_id=p_owner and request_id=p_request and role='user';
  if not c.memory_enabled or c.consent_version<>j.consent_version or m.created_at<=c.memory_reset_at then
    update public.memory_jobs set status='suppressed',updated_at=now() where request_id=p_request;
    return jsonb_build_object('saved',0);
  end if;
  if jsonb_typeof(p_candidates)<>'array' or jsonb_array_length(p_candidates)>5 then raise exception 'invalid_input'; end if;
  for candidate in select value from jsonb_array_elements(p_candidates) loop
    fact_key=candidate->>'key';quote=btrim(candidate->>'quote');category=candidate->>'category';
    if fact_key is null or fact_key !~ '^[a-z0-9_.:-]{1,120}$' or quote is null
      or length(quote) not between 4 and 2000 or position(quote in m.content)=0
      or coalesce((candidate->>'confidence')::real,0)<0.8 then continue; end if;
    if exists(select 1 from public.memory_tombstones where owner_id=p_owner
      and companion_id=c.id and memory_key=fact_key) then continue; end if;
    -- Automatic facts are VERBATIM quotes, not unverified model paraphrases.
    insert into public.memories(owner_id,companion_id,memory_key,category,title,content,
      source_quote,source_message_id,confidence,importance,expires_at)
    values(p_owner,c.id,fact_key,category,left(quote,80),quote,quote,m.id,
      (candidate->>'confidence')::real,(candidate->>'importance')::real,
      case when c.retention_days is null then null else now()+make_interval(days=>c.retention_days) end)
    on conflict(owner_id,companion_id,memory_key) do update set category=excluded.category,
      title=excluded.title,content=excluded.content,source_quote=excluded.source_quote,
      source_message_id=excluded.source_message_id,confidence=excluded.confidence,
      importance=excluded.importance,updated_at=now(),expires_at=excluded.expires_at
      where not memories.user_edited;
    if found then total=total+1; end if;
  end loop;
  update public.memory_jobs set status='completed',updated_at=now() where request_id=p_request;
  return jsonb_build_object('saved',total);
end; $$;

create function public.morrow_fail_memory_job(p_owner text,p_request uuid,p_lease uuid)
returns jsonb language sql security invoker set search_path='' as $$
  with changed as (update public.memory_jobs set status='failed',updated_at=now()
    where owner_id=p_owner and request_id=p_request and lease=p_lease and status='running' returning 1)
  select jsonb_build_object('ok',true);
$$;

create function public.morrow_search_memories(p_owner text,p_companion uuid,p_query text,p_limit integer default 8)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare q tsquery;result jsonb;
begin
  if not exists(select 1 from public.companions where owner_id=p_owner and id=p_companion and memory_enabled)
    then return jsonb_build_object('memories','[]'::jsonb); end if;
  delete from public.memories where owner_id=p_owner and expires_at<=now();
  q=websearch_to_tsquery('simple',left(p_query,2000));
  select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) into result from (
    select id,category,content,title,
      ts_rank_cd(search_vector,q)*0.6+importance*0.3+
        (0.1/(1+extract(epoch from(now()-updated_at))/86400/30))::real as relevance
    from public.memories where owner_id=p_owner and companion_id=p_companion
      and (expires_at is null or expires_at>now())
    order by (search_vector @@ q) desc,relevance desc,updated_at desc
    limit greatest(1,least(p_limit,8)))m;
  return jsonb_build_object('memories',result);
end; $$;

create function public.morrow_list_memories(p_owner text,p_companion uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;total integer;
begin
  if not exists(select 1 from public.companions where id=p_companion and owner_id=p_owner)
    then raise exception 'not_found'; end if;
  delete from public.memories where owner_id=p_owner and expires_at<=now();
  select count(*) into total from public.memories where owner_id=p_owner and companion_id=p_companion;
  select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) into result from (
    select id,memory_key,category,title,content,source_message_id,source_quote,user_edited,created_at,updated_at,expires_at
    from public.memories where owner_id=p_owner and companion_id=p_companion
    order by updated_at desc limit 100)m;
  return jsonb_build_object('memories',result,'total',total,'pending_count',
    (select count(*) from public.memory_jobs where owner_id=p_owner and companion_id=p_companion
      and status in ('pending','running','failed') and attempts<5));
end; $$;

create function public.morrow_save_memory(p_owner text,p_companion uuid,p_id uuid,
  p_category text,p_title text,p_content text,p_expires_at timestamptz)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.companions;result jsonb;expiry timestamptz;
begin
  select * into c from public.companions where owner_id=p_owner and id=p_companion for update;
  if not found then raise exception 'not_found'; end if;
  expiry=p_expires_at;
  if c.retention_days is not null then expiry=least(coalesce(expiry,'infinity'),now()+make_interval(days=>c.retention_days)); end if;
  if expiry is not null and expiry<=now() then raise exception 'invalid_input'; end if;
  if p_id is null then
    insert into public.memories(owner_id,companion_id,memory_key,category,title,content,user_edited,user_expires_at,expires_at)
      values(p_owner,p_companion,'manual.'||gen_random_uuid()::text,p_category,p_title,p_content,true,p_expires_at,expiry)
      returning to_jsonb(memories.*) into result;
  else
    update public.memories set category=p_category,title=p_title,content=p_content,user_edited=true,
      user_expires_at=p_expires_at,expires_at=expiry,updated_at=now() where id=p_id and owner_id=p_owner and companion_id=p_companion
      returning to_jsonb(memories.*) into result;
    if not found then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('memory',result);
end; $$;

create function public.morrow_forget_memory(p_owner text,p_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare m public.memories;
begin
  -- Serialize individual deletion with extraction before locking the memory.
  perform 1 from public.companions comp join public.memories mem on mem.companion_id=comp.id
    where mem.id=p_id and mem.owner_id=p_owner and comp.owner_id=p_owner for update of comp;
  select * into m from public.memories where owner_id=p_owner and id=p_id for update;
  if not found then raise exception 'not_found'; end if;
  insert into public.memory_tombstones(owner_id,companion_id,memory_key)
    values(p_owner,m.companion_id,m.memory_key) on conflict do nothing;
  delete from public.memories where owner_id=p_owner and id=p_id;
  return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_forget_all_memories(p_owner text,p_companion uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  update public.companions set memory_reset_at=clock_timestamp(),consent_version=consent_version+1
    where owner_id=p_owner and id=p_companion;
  if not found then raise exception 'not_found'; end if;
  delete from public.memories where owner_id=p_owner and companion_id=p_companion;
  update public.memory_jobs set status='suppressed',updated_at=now()
    where owner_id=p_owner and companion_id=p_companion and status<>'completed';
  return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_apply_retention() returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if new.retention_days is distinct from old.retention_days then
    delete from public.memories where owner_id=new.owner_id and companion_id=new.id and expires_at<=now();
    update public.memories set expires_at=case when new.retention_days is null then user_expires_at
      else least(coalesce(user_expires_at,'infinity'),updated_at+make_interval(days=>new.retention_days)) end
      where owner_id=new.owner_id and companion_id=new.id;
    delete from public.memories where owner_id=new.owner_id and companion_id=new.id and expires_at<=now();
  end if;
  return new;
end; $$;
create trigger apply_memory_retention after update of retention_days on public.companions
  for each row execute function public.morrow_apply_retention();

-- Schedule this server-only cleanup daily after the target project audit.
create function public.morrow_purge_expired_memories() returns bigint
language plpgsql security invoker set search_path='' as $$
declare total bigint;
begin delete from public.memories where expires_at<=now();get diagnostics total=row_count;return total;end; $$;

revoke all on function public.morrow_enqueue_memory(),public.morrow_apply_retention(),
  public.morrow_claim_memory_job(text,uuid),public.morrow_apply_memory_job(text,uuid,uuid,jsonb),
  public.morrow_fail_memory_job(text,uuid,uuid),public.morrow_search_memories(text,uuid,text,integer),
  public.morrow_list_memories(text,uuid),public.morrow_save_memory(text,uuid,uuid,text,text,text,timestamptz),
  public.morrow_forget_memory(text,uuid),public.morrow_forget_all_memories(text,uuid),
  public.morrow_purge_expired_memories() from public,anon,authenticated;
grant execute on function public.morrow_enqueue_memory(),public.morrow_apply_retention(),
  public.morrow_claim_memory_job(text,uuid),public.morrow_apply_memory_job(text,uuid,uuid,jsonb),
  public.morrow_fail_memory_job(text,uuid,uuid),public.morrow_search_memories(text,uuid,text,integer),
  public.morrow_list_memories(text,uuid),public.morrow_save_memory(text,uuid,uuid,text,text,text,timestamptz),
  public.morrow_forget_memory(text,uuid),public.morrow_forget_all_memories(text,uuid),
  public.morrow_purge_expired_memories() to service_role;
-- END 202611020004_memories.sql

-- BEGIN 202611020005_memory_recovery.sql
create function public.morrow_pending_memory_jobs(p_owner text)
returns jsonb language sql security invoker set search_path='' as $$
  select jsonb_build_object('requests',coalesce(jsonb_agg(request_id),'[]'::jsonb)) from (
    select request_id from public.memory_jobs where owner_id=p_owner and attempts<5
      and (status in ('pending','failed') or (status='running' and lease_until<now()))
    order by created_at limit 3)j;
$$;
revoke all on function public.morrow_pending_memory_jobs(text) from public,anon,authenticated;
grant execute on function public.morrow_pending_memory_jobs(text) to service_role;
-- END 202611020005_memory_recovery.sql

-- BEGIN 202611020006_personalization.sql
-- Local candidate: independent consent; no psychological or demographic inference.
alter table public.companions add column learning_enabled boolean not null default false;
create table public.interaction_patterns (
  owner_id text not null references public.profiles(user_id) on delete cascade,
  companion_id uuid primary key,
  completed_turns bigint not null default 0 check (completed_turns>=0),
  user_characters bigint not null default 0 check (user_characters>=0),
  updated_at timestamptz not null default now(),
  foreign key(owner_id,companion_id) references public.companions(owner_id,id) on delete cascade
);
alter table public.interaction_patterns enable row level security;
create policy own_patterns_read on public.interaction_patterns for select to authenticated
using (owner_id=(select auth.jwt()->>'sub') and
  (select auth.jwt()->>'iss') like 'https://securetoken.google.com/%');
revoke all on public.interaction_patterns from public,anon,authenticated;
grant select on public.interaction_patterns to authenticated;
grant all on public.interaction_patterns to service_role;

create function public.morrow_set_learning(p_owner text,p_companion uuid,p_enabled boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.companions;
begin
  update public.companions set learning_enabled=p_enabled,updated_at=now()
    where owner_id=p_owner and id=p_companion returning * into c;
  if not found then raise exception 'not_found'; end if;
  if not p_enabled then delete from public.interaction_patterns
    where owner_id=p_owner and companion_id=p_companion; end if;
  return jsonb_build_object('companion',to_jsonb(c));
end; $$;

create function public.morrow_observe_turn() returns trigger
language plpgsql security invoker set search_path='' as $$
declare c public.companions; chars integer;
begin
  if new.status<>'completed' or old.status='completed' then return new; end if;
  select comp.* into c from public.companions comp join public.conversations conv
    on conv.companion_id=comp.id and conv.owner_id=comp.owner_id
    where conv.id=new.conversation_id and comp.owner_id=new.owner_id for update of comp;
  if not found or not c.learning_enabled then return new; end if;
  select length(content) into chars from public.messages
    where request_id=new.id and owner_id=new.owner_id and role='user';
  insert into public.interaction_patterns(owner_id,companion_id,completed_turns,user_characters)
    values(new.owner_id,c.id,1,coalesce(chars,0))
    on conflict(companion_id) do update set completed_turns=interaction_patterns.completed_turns+1,
      user_characters=interaction_patterns.user_characters+excluded.user_characters,updated_at=now();
  return new;
end; $$;
create trigger observe_completed_turn after update of status on public.turn_requests
for each row execute function public.morrow_observe_turn();

create function public.morrow_personalization(p_owner text,p_companion uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
  if not exists(select 1 from public.companions where id=p_companion and owner_id=p_owner)
    then raise exception 'not_found'; end if;
  select jsonb_build_object('completed_turns',p.completed_turns,
    'average_user_characters',round(p.user_characters::numeric/greatest(p.completed_turns,1)))
    into result from public.interaction_patterns p join public.companions c on c.id=p.companion_id
    where p.owner_id=p_owner and p.companion_id=p_companion and c.learning_enabled;
  return jsonb_build_object('observations',result);
end; $$;
revoke all on function public.morrow_set_learning(text,uuid,boolean),public.morrow_observe_turn(),
  public.morrow_personalization(text,uuid) from public,anon,authenticated;
grant execute on function public.morrow_set_learning(text,uuid,boolean),public.morrow_observe_turn(),
  public.morrow_personalization(text,uuid) to service_role;
-- END 202611020006_personalization.sql

-- BEGIN 202611020007_proactivity.sql
-- Local candidate. No schedule becomes active without explicit complete preferences.
create table public.notification_preferences (
  owner_id text primary key references public.profiles(user_id) on delete cascade,
  companion_id uuid not null,
  checkins_enabled boolean not null default false,
  suggestions_enabled boolean not null default false,
  birthdays_enabled boolean not null default false,
  timezone text,
  local_minute integer not null default 1140 check(local_minute between 0 and 1439),
  weekdays integer[] not null default array[0,1,2,3,4,5,6]
    check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[0,1,2,3,4,5,6]),
  quiet_start integer not null default 1320 check(quiet_start between 0 and 1439),
  quiet_end integer not null default 480 check(quiet_end between 0 and 1439),
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  foreign key(owner_id,companion_id) references public.companions(owner_id,id) on delete cascade
);
create table public.device_tokens (
  owner_id text not null references public.profiles(user_id) on delete cascade,
  installation_id uuid not null,
  token text not null unique check(length(token) between 20 and 4096),
  updated_at timestamptz not null default now(),
  primary key(owner_id,installation_id)
);
create table public.scheduled_checkins (
  id uuid primary key default gen_random_uuid(),
  owner_id text not null references public.profiles(user_id) on delete cascade,
  kind text not null check(kind in ('checkin','followup','important_date')),
  due_at timestamptz not null,
  local_date date,
  status text not null default 'queued' check(status in ('queued','sending','sent','suppressed','failed','unknown')),
  lease uuid,
  lease_until timestamptz,
  preference_revision bigint not null,
  created_at timestamptz not null default now()
);
create unique index one_daily_checkin on public.scheduled_checkins(owner_id,local_date) where local_date is not null;
create index due_checkins on public.scheduled_checkins(due_at) where status='queued';
do $$ declare t text; begin
  foreach t in array array['notification_preferences','device_tokens','scheduled_checkins'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant all on public.%I to service_role',t);
  end loop;
end; $$;
create policy own_notification_preferences on public.notification_preferences for select to authenticated
using(owner_id=(select auth.jwt()->>'sub') and (select auth.jwt()->>'iss') like 'https://securetoken.google.com/%');
grant select on public.notification_preferences to authenticated;

create function public.morrow_is_quiet(p_minute integer,p_start integer,p_end integer)
returns boolean language sql immutable set search_path='' as $$
select case when p_start=p_end then false when p_start<p_end then p_minute>=p_start and p_minute<p_end
 else p_minute>=p_start or p_minute<p_end end;
$$;
create function public.morrow_notification_preferences(p_owner text)
returns jsonb language sql security invoker set search_path='' as $$
select jsonb_build_object('preferences',(select to_jsonb(p) from public.notification_preferences p where p.owner_id=p_owner));
$$;
create function public.morrow_save_notification_preferences(p_owner text,p_companion uuid,
 p_checkins boolean,p_suggestions boolean,p_birthdays boolean,p_timezone text,p_local_minute integer,
 p_weekdays integer[],p_quiet_start integer,p_quiet_end integer)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
  if not exists(select 1 from public.companions where id=p_companion and owner_id=p_owner)
    then raise exception 'not_found'; end if;
  if p_checkins is null or p_suggestions is null or p_birthdays is null
    or p_local_minute is null or p_quiet_start is null or p_quiet_end is null or p_weekdays is null
    or (p_timezone is not null and not exists(select 1 from pg_timezone_names where name=p_timezone))
    or ((p_checkins or p_suggestions or p_birthdays) and (p_timezone is null or cardinality(p_weekdays)=0
      or public.morrow_is_quiet(p_local_minute,p_quiet_start,p_quiet_end)))
    then raise exception 'invalid_input'; end if;
  insert into public.notification_preferences(owner_id,companion_id,checkins_enabled,suggestions_enabled,
    birthdays_enabled,timezone,local_minute,weekdays,quiet_start,quiet_end)
    values(p_owner,p_companion,p_checkins,p_suggestions,p_birthdays,p_timezone,p_local_minute,
      p_weekdays,p_quiet_start,p_quiet_end)
    on conflict(owner_id) do update set checkins_enabled=p_checkins,suggestions_enabled=p_suggestions,
      birthdays_enabled=p_birthdays,timezone=p_timezone,local_minute=p_local_minute,weekdays=p_weekdays,
      quiet_start=p_quiet_start,quiet_end=p_quiet_end,revision=notification_preferences.revision+1,updated_at=now()
    returning to_jsonb(notification_preferences.*) into result;
  update public.scheduled_checkins set status='suppressed' where owner_id=p_owner and status='queued';
  return jsonb_build_object('preferences',result);
end; $$;
create function public.morrow_register_device(p_owner text,p_installation uuid,p_token text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  -- A token can belong to one current identity only; switching accounts transfers it.
  delete from public.device_tokens where token=p_token and owner_id<>p_owner;
  insert into public.device_tokens(owner_id,installation_id,token) values(p_owner,p_installation,p_token)
    on conflict(owner_id,installation_id) do update set token=p_token,updated_at=now();
  return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_unregister_device(p_owner text,p_installation uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin delete from public.device_tokens where owner_id=p_owner and installation_id=p_installation;
return jsonb_build_object('ok',true); end; $$;
create function public.morrow_schedule_followup(p_owner text,p_kind text,p_due timestamptz)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; p public.notification_preferences;
begin
  select * into p from public.notification_preferences where owner_id=p_owner for update;
  if not found or p.timezone is null or p_due<=now() or p_due>now()+interval '366 days'
    or p_kind not in ('followup','important_date')
    or (p_kind='followup' and not p.checkins_enabled)
    or (p_kind='important_date' and not p.birthdays_enabled)
    then raise exception 'invalid_input'; end if;
  if (select count(*) from public.scheduled_checkins where owner_id=p_owner and status='queued')>=100
    then raise exception 'rate_limited'; end if;
  insert into public.scheduled_checkins(owner_id,kind,due_at,preference_revision)
    values(p_owner,p_kind,p_due,p.revision) returning to_jsonb(scheduled_checkins.*) into result;
  return jsonb_build_object('checkin',result);
end; $$;
create function public.morrow_cancel_checkin(p_owner text,p_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin update public.scheduled_checkins set status='suppressed' where owner_id=p_owner and id=p_id and status='queued';
return jsonb_build_object('ok',true); end; $$;

create function public.morrow_due_checkins(p_now timestamptz default now(),p_limit integer default 20)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare p public.notification_preferences; local_time timestamp; minute integer;
  job public.scheduled_checkins; result jsonb='[]'; devices jsonb;
begin
  -- Ambiguous previous deliveries are not automatically resent after a worker crash.
  update public.scheduled_checkins set status='unknown' where status='sending' and lease_until<p_now;
  update public.scheduled_checkins set status='suppressed' where status='queued' and due_at<p_now-interval '1 day';
  for p in select * from public.notification_preferences where timezone is not null
    and (checkins_enabled or suggestions_enabled or birthdays_enabled) order by owner_id for update skip locked loop
    local_time=p_now at time zone p.timezone;
    minute=extract(hour from local_time)::integer*60+extract(minute from local_time)::integer;
    if public.morrow_is_quiet(minute,p.quiet_start,p.quiet_end)
      or not extract(dow from local_time)::integer=any(p.weekdays) then continue; end if;
    if not exists(select 1 from public.device_tokens where owner_id=p.owner_id and updated_at>p_now-interval '90 days')
      then continue; end if;
    if exists(select 1 from public.scheduled_checkins where owner_id=p.owner_id and local_date=local_time::date) then continue; end if;
    if (p.checkins_enabled or p.suggestions_enabled) and minute>=p.local_minute and minute<p.local_minute+60 then
      insert into public.scheduled_checkins(owner_id,kind,due_at,preference_revision)
        select p.owner_id,'checkin',p_now,p.revision where not exists(
          select 1 from public.scheduled_checkins where owner_id=p.owner_id and status='queued' and kind='checkin') ;
    end if;
    select * into job from public.scheduled_checkins where owner_id=p.owner_id and status='queued' and due_at<=p_now
      and preference_revision=p.revision and ((kind='checkin' and (p.checkins_enabled or p.suggestions_enabled))
        or (kind='followup' and p.checkins_enabled) or (kind='important_date' and p.birthdays_enabled))
      order by due_at,id limit 1 for update;
    if not found then continue; end if;
    update public.scheduled_checkins set status='sending',local_date=local_time::date,lease=gen_random_uuid(),
      lease_until=p_now+interval '2 minutes' where id=job.id returning * into job;
    select jsonb_agg(jsonb_build_object('installation_id',installation_id,'token',token)) into devices
      from public.device_tokens where owner_id=p.owner_id and updated_at>p_now-interval '90 days';
    result=result||jsonb_build_array(jsonb_build_object('id',job.id,'lease',job.lease,'owner_id',job.owner_id,'devices',devices));
    exit when jsonb_array_length(result)>=least(greatest(p_limit,1),100);
  end loop;
  return jsonb_build_object('jobs',result);
end; $$;
create function public.morrow_notification_ttl(p_now timestamptz,p_timezone text,p_start integer,p_end integer)
returns integer language sql stable set search_path='' as $$
select case when p_start=p_end then 300 else greatest(0,least(300,
  mod(p_start*60-floor(extract(epoch from (p_now at time zone p_timezone)::time))::integer+86400,86400))) end;
$$;
create function public.morrow_authorize_checkin(p_id uuid,p_lease uuid)
returns jsonb language sql security invoker set search_path='' as $$
select jsonb_build_object('allowed',exists(select 1 from public.scheduled_checkins j
  join public.notification_preferences p on p.owner_id=j.owner_id
  where j.id=p_id and j.lease=p_lease and j.status='sending' and j.lease_until>now()
    and j.preference_revision=p.revision and p.timezone is not null
    and not public.morrow_is_quiet(extract(hour from now() at time zone p.timezone)::integer*60+
      extract(minute from now() at time zone p.timezone)::integer,p.quiet_start,p.quiet_end)),
  'ttl_seconds',coalesce((select public.morrow_notification_ttl(now(),p.timezone,p.quiet_start,p.quiet_end)
    from public.scheduled_checkins j join public.notification_preferences p on p.owner_id=j.owner_id
    where j.id=p_id and j.lease=p_lease),0));
$$;
create function public.morrow_finish_checkin(p_id uuid,p_lease uuid,p_status text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  if p_status not in ('sent','failed','unknown','suppressed') then raise exception 'invalid_input'; end if;
  update public.scheduled_checkins set status=p_status where id=p_id and lease=p_lease and status='sending';
  return jsonb_build_object('ok',true);
end; $$;
do $$ declare fn regprocedure; begin
  for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
    'morrow_is_quiet','morrow_notification_preferences','morrow_save_notification_preferences',
    'morrow_register_device','morrow_unregister_device','morrow_schedule_followup','morrow_cancel_checkin',
    'morrow_due_checkins','morrow_notification_ttl','morrow_authorize_checkin','morrow_finish_checkin') loop
    execute format('revoke all on function %s from public,anon,authenticated',fn);
    execute format('grant execute on function %s to service_role',fn);
  end loop;
end; $$;
-- END 202611020007_proactivity.sql

-- BEGIN 202611020008_voice.sql
alter table public.companions add column voice_enabled boolean not null default false;
create table public.voice_usage (
  id bigint generated always as identity primary key,
  owner_id text not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now()
);
create index voice_usage_window on public.voice_usage(owner_id,created_at);
alter table public.voice_usage enable row level security;
revoke all on public.voice_usage from public,anon,authenticated;
grant all on public.voice_usage to service_role;
grant usage on sequence public.voice_usage_id_seq to service_role;
create function public.morrow_set_voice(p_owner text,p_companion uuid,p_enabled boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
  update public.companions set voice_enabled=p_enabled,updated_at=now() where id=p_companion and owner_id=p_owner
    returning to_jsonb(companions.*) into result;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('companion',result);
end; $$;
create function public.morrow_authorize_voice(p_owner text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
  perform 1 from public.companions where owner_id=p_owner and voice_enabled for update;
  if not found then raise exception 'consent_required'; end if;
  delete from public.voice_usage where owner_id=p_owner and created_at<now()-interval '1 day';
  if (select count(*) from public.voice_usage where owner_id=p_owner and created_at>now()-interval '1 minute')>=12
    then raise exception 'rate_limited'; end if;
  insert into public.voice_usage(owner_id) values(p_owner);
  return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_voice_message(p_owner text,p_message uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
  select jsonb_build_object('content',m.content) into result from public.messages m
    join public.conversations conv on conv.id=m.conversation_id and conv.owner_id=m.owner_id
    join public.companions comp on comp.id=conv.companion_id and comp.owner_id=m.owner_id
    where m.id=p_message and m.owner_id=p_owner and m.role='assistant' and m.status='completed' and comp.voice_enabled;
  if not found then raise exception 'not_found'; end if;
  return result;
end; $$;
revoke all on function public.morrow_set_voice(text,uuid,boolean),public.morrow_authorize_voice(text),
  public.morrow_voice_message(text,uuid) from public,anon,authenticated;
grant execute on function public.morrow_set_voice(text,uuid,boolean),public.morrow_authorize_voice(text),
  public.morrow_voice_message(text,uuid) to service_role;
-- END 202611020008_voice.sql

-- BEGIN 202611020009_privacy.sql
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
-- END 202611020009_privacy.sql

-- BEGIN 202611030010_companion_continuity.sql
-- Additive local candidate. Inspect the target schema/history before deployment.
alter table public.profiles add column preferred_name text check(length(preferred_name)<=80),
 add column timezone text, add column language text check(length(language)<=40),
 add column general_location text check(length(general_location)<=120);
alter table public.companions add column introduced_at timestamptz,
 add column name_question_asked_at timestamptz;
alter table public.turn_requests add column kind text not null default 'user'
 check(kind in ('user','greeting','proactive')), add column context_timezone text,
 add column greeting_asks_name boolean not null default false;
create unique index one_conversation_greeting on public.turn_requests(conversation_id) where kind='greeting';

create function public.morrow_memory_kind(p_category text) returns text
language sql immutable set search_path='' as $$
 select case p_category when 'personal_information' then 'identity' when 'identity' then 'identity'
 when 'routines' then 'routine' when 'preferences' then 'preference' when 'communication_preferences' then 'preference'
 when 'people' then 'relationship' when 'relationships' then 'relationship'
 when 'important_dates' then 'event' when 'events' then 'event'
 when 'goals' then 'development' when 'personal_development' then 'development'
 else 'conversation' end;
$$;
alter table public.memories drop constraint memories_category_check;
alter table public.memories add constraint memories_category_check check(category in (
 'personal_information','preferences','people','experiences','important_dates','goals','discussions','communication_preferences',
 'identity','routines','relationships','events','conversation_history','personal_development'));
alter table public.memories add column kind text generated always as (public.morrow_memory_kind(category)) stored,
 add column attributes jsonb not null default '{}'::jsonb check(jsonb_typeof(attributes)='object'),
 add column verification text not null default 'user_stated' check(verification in ('user_stated','user_confirmed','unverified','superseded')),
 add column temporal_status text not null default 'durable' check(temporal_status in ('durable','temporary','planned','completed','cancelled','unresolved'));
create index continuity_memory_lookup on public.memories(owner_id,companion_id,kind,updated_at desc);

create function public.morrow_save_personal_profile(p_owner text,p_preferred_name text,p_display_name text,
 p_timezone text,p_language text,p_location text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb; begin
 if p_timezone is not null and not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'invalid_input'; end if;
 update public.profiles set preferred_name=nullif(btrim(p_preferred_name),''),display_name=nullif(btrim(p_display_name),''),
 timezone=p_timezone,language=nullif(btrim(p_language),''),general_location=nullif(btrim(p_location),''),updated_at=now()
 where user_id=p_owner returning to_jsonb(profiles.*) into result;
 if not found then raise exception 'not_found'; end if;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_snapshot_context() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 select coalesce(p.timezone,n.timezone) into new.context_timezone from public.profiles p
 left join public.notification_preferences n on n.owner_id=p.user_id where p.user_id=new.owner_id;
 if new.context_timezone is null then
  select m.attributes->>'value' into new.context_timezone from public.memories m join public.companions c on c.id=m.companion_id and c.owner_id=m.owner_id
  where m.owner_id=new.owner_id and c.memory_enabled and m.kind='identity' and m.attributes->>'field'='timezone'
   and m.verification not in ('unverified','superseded') and (m.expires_at is null or m.expires_at>now()) order by m.user_edited desc,m.updated_at desc limit 1;
 end if;
 if new.context_timezone is not null and not exists(select 1 from pg_timezone_names where name=new.context_timezone) then new.context_timezone=null; end if;
 return new;
end; $$;
create trigger snapshot_turn_context before insert on public.turn_requests for each row execute function public.morrow_snapshot_context();

create function public.morrow_normalize_attributes(p_attributes jsonb,p_quote text,p_source_time timestamptz,p_zone text,p_manual boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare a jsonb=coalesce(p_attributes,'{}'); result jsonb='{}'; item jsonb; key text; z text=p_zone; d date; relative integer;
begin
 if jsonb_typeof(a)<>'object' or pg_column_size(a)>4000 then raise exception 'invalid_input'; end if;
 for key,item in select * from jsonb_each(a) loop
   if key not in ('field','value','weekdays','start_minute','end_minute','on_date','relative_days','timezone','routine_kind','skip','block_notifications','stability','event_status','annual','month','day')
     then raise exception 'invalid_input'; end if;
 end loop;
 if a->>'field' is not null then
   if a->>'field' not in ('preferred_name','full_name','location','language','timezone','wake','sleep','work','study','exercise','activity','other') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('field',a->>'field');
 end if;
 if a->>'value' is not null then
   if length(a->>'value') not between 1 and 160 or (not p_manual and position(lower(a->>'value') in lower(p_quote))=0) then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('value',a->>'value');
 end if;
 foreach key in array array['start_minute','end_minute'] loop
   if a->>key is not null then
     if a->>key !~ '^\d{1,4}$' or (a->>key)::integer not between 0 and 1439 then raise exception 'invalid_input'; end if;
     result=result||jsonb_build_object(key,(a->>key)::integer);
   end if;
 end loop;
 if a->'weekdays' is not null and a->'weekdays'<>'null' then
   if jsonb_typeof(a->'weekdays')<>'array' or jsonb_array_length(a->'weekdays')>7 then raise exception 'invalid_input'; end if;
   for item in select value from jsonb_array_elements(a->'weekdays') loop
     if item::text !~ '^[0-6]$' then raise exception 'invalid_input'; end if;
   end loop;
   result=result||jsonb_build_object('weekdays',a->'weekdays');
 end if;
 foreach key in array array['skip','block_notifications','annual'] loop
   if a->>key is not null then
     if jsonb_typeof(a->key)<>'boolean' then raise exception 'invalid_input'; end if;
     result=result||jsonb_build_object(key,a->key);
   end if;
 end loop;
 if a->>'annual'='true' then
  if a->>'month' !~ '^\d{1,2}$' or a->>'day' !~ '^\d{1,2}$' or a->>'month' is null or a->>'day' is null then raise exception 'invalid_input'; end if;
  perform make_date(2000,(a->>'month')::integer,(a->>'day')::integer);
  if not p_manual and p_quote !~* '(birthday|anniversary|annually|every year|each year)' then raise exception 'invalid_input'; end if;
  result=result||jsonb_build_object('month',(a->>'month')::integer,'day',(a->>'day')::integer);
 end if;
 if a->>'routine_kind' is not null then
   if a->>'routine_kind' not in ('wake','sleep','work','study','exercise','activity','other') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('routine_kind',a->>'routine_kind');
 end if;
 if a->>'stability' is not null then
   if a->>'stability' not in ('durable','temporary','event','uncertain') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('stability',a->>'stability');
 end if;
 if a->>'event_status' is not null then
   if a->>'event_status' not in ('planned','completed','cancelled','uncertain') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('event_status',a->>'event_status');
 end if;
 if a->>'timezone' is not null and (p_manual or position(a->>'timezone' in p_quote)>0) then z=a->>'timezone'; end if;
 if z is not null and not exists(select 1 from pg_timezone_names where name=z) then raise exception 'invalid_input'; end if;
 if z is not null then result=result||jsonb_build_object('timezone',z); end if;
 if a->>'relative_days' is not null then
   if a->>'relative_days' !~ '^-?\d{1,3}$' then raise exception 'invalid_input'; end if;
   relative=(a->>'relative_days')::integer;
   if relative not between -1 and 366 then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('relative_days',relative,'observed_at',p_source_time);
   if z is not null then d=(p_source_time at time zone z)::date+relative; end if;
 end if;
 if a->>'on_date' is not null then
   if a->>'on_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_input'; end if;
   if p_manual or position(a->>'on_date' in p_quote)>0 then d=(a->>'on_date')::date; end if;
 end if;
 if d is not null then result=result||jsonb_build_object('on_date',d); end if;
 return result;
end; $$;

-- Old clients can still edit plain memories. Clear structured data when they
-- change the words without supplying a corresponding structured correction.
create function public.morrow_clear_stale_attributes() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.content is distinct from old.content or new.category is distinct from old.category or new.source_message_id is distinct from old.source_message_id) then
   new.attributes='{}';new.verification=case when new.user_edited then 'user_confirmed' else 'user_stated' end;new.temporal_status='durable';
 end if;
 return new;
end; $$;
create trigger clear_stale_attributes before update of content,category,source_message_id on public.memories
 for each row execute function public.morrow_clear_stale_attributes();

create function public.morrow_save_structured_memory(p_owner text,p_companion uuid,p_id uuid,
 p_category text,p_title text,p_content text,p_expires_at timestamptz,p_attributes jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; a jsonb; z text; begin
 select coalesce(p.timezone,n.timezone) into z from public.profiles p left join public.notification_preferences n on n.owner_id=p.user_id where p.user_id=p_owner;
 a=public.morrow_normalize_attributes(p_attributes,p_content,now(),z,true);
 result=public.morrow_save_memory(p_owner,p_companion,p_id,p_category,p_title,p_content,p_expires_at);
 update public.memories set attributes=a,verification='user_confirmed',
 temporal_status=case when a->>'event_status'='cancelled' then 'cancelled' when a->>'annual'='true' then 'durable' when a->>'event_status'='completed' then 'completed'
 when a->>'stability'='uncertain' then 'unresolved' when a->>'stability'='temporary' then 'temporary'
 when kind='event' and a->>'on_date' is null then 'unresolved' when kind='event' then 'planned' else 'durable' end
 where id=(result->'memory'->>'id')::uuid and owner_id=p_owner returning to_jsonb(memories.*) into result;
 return jsonb_build_object('memory',result);
end; $$;

-- Preserve the original consent/lease/tombstone fences while allowing a short
-- explicitly grounded preferred name (for example Li) after the name question.
create or replace function public.morrow_apply_memory_job(p_owner text,p_request uuid,p_lease uuid,p_candidates jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.memory_jobs;c public.companions;m public.messages;candidate jsonb;
 fact_key text;quote text;category text;total integer=0;
begin
 select comp.* into c from public.companions comp join public.memory_jobs job on job.companion_id=comp.id
  where job.request_id=p_request and job.owner_id=p_owner and comp.owner_id=p_owner for update of comp;
 select * into j from public.memory_jobs where request_id=p_request and owner_id=p_owner for update;
 if not found or j.status<>'running' or j.lease<>p_lease or j.lease_until<now() then raise exception 'stale_turn'; end if;
 select * into m from public.messages where owner_id=p_owner and request_id=p_request and role='user';
 if not c.memory_enabled or c.consent_version<>j.consent_version or m.created_at<=c.memory_reset_at then
  update public.memory_jobs set status='suppressed',updated_at=now() where request_id=p_request;
  return jsonb_build_object('saved',0);
 end if;
 if jsonb_typeof(p_candidates)<>'array' or jsonb_array_length(p_candidates)>5 then raise exception 'invalid_input'; end if;
 for candidate in select value from jsonb_array_elements(p_candidates) loop
  fact_key=candidate->>'key';quote=btrim(candidate->>'quote');category=candidate->>'category';
  if fact_key is null or fact_key !~ '^[a-z0-9_.:-]{1,120}$' or quote is null or length(quote)>2000
   or length(quote)<(case when candidate->'attributes'->>'field'='preferred_name' then 1 else 4 end)
   or position(quote in m.content)=0 or coalesce((candidate->>'confidence')::real,0)<.8 then continue; end if;
  if exists(select 1 from public.memory_tombstones where owner_id=p_owner and companion_id=c.id and memory_key=fact_key) then continue; end if;
  insert into public.memories(owner_id,companion_id,memory_key,category,title,content,source_quote,source_message_id,confidence,importance,expires_at)
   values(p_owner,c.id,fact_key,category,left(quote,80),quote,quote,m.id,(candidate->>'confidence')::real,(candidate->>'importance')::real,
    case when c.retention_days is null then null else now()+make_interval(days=>c.retention_days) end)
   on conflict(owner_id,companion_id,memory_key) do update set category=excluded.category,title=excluded.title,content=excluded.content,
    source_quote=excluded.source_quote,source_message_id=excluded.source_message_id,confidence=excluded.confidence,
    importance=excluded.importance,updated_at=now(),expires_at=excluded.expires_at where not memories.user_edited;
  if found then total=total+1; end if;
 end loop;
 update public.memory_jobs set status='completed',updated_at=now() where request_id=p_request;
 return jsonb_build_object('saved',total);
end; $$;

create function public.morrow_apply_companion_memory_job(p_owner text,p_request uuid,p_lease uuid,p_candidates jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; candidate jsonb; m public.messages; r public.turn_requests; a jsonb; stability text; expiry timestamptz;
begin
 result=public.morrow_apply_memory_job(p_owner,p_request,p_lease,p_candidates);
 if coalesce((result->>'saved')::integer,0)=0 then return result; end if;
 select * into m from public.messages where owner_id=p_owner and request_id=p_request and role='user';
 select * into r from public.turn_requests where owner_id=p_owner and id=p_request;
 for candidate in select value from jsonb_array_elements(p_candidates) loop
   a=public.morrow_normalize_attributes(candidate->'attributes',candidate->>'quote',m.created_at,r.context_timezone,false);
   stability=coalesce(a->>'stability','durable');
   expiry=case when stability='temporary' then m.created_at+interval '7 days'
     when public.morrow_memory_kind(candidate->>'category')='event' and a->>'annual' is distinct from 'true' then
       case when a->>'on_date' is not null and a->>'timezone' is not null
        then ((a->>'on_date')::date+30)::timestamp at time zone (a->>'timezone') else m.created_at+interval '30 days' end else null end;
   update public.memories set attributes=a,verification=case when stability='uncertain' then 'unverified' else 'user_stated' end,
    temporal_status=case when a->>'event_status'='cancelled' then 'cancelled' when a->>'annual'='true' then 'durable' when a->>'event_status'='completed' then 'completed'
     when stability='uncertain' then 'unresolved' when stability='temporary' then 'temporary'
     when kind='event' and a->>'on_date' is null then 'unresolved' when kind='event' then 'planned' else 'durable' end,
    expires_at=least(expires_at,expiry)
   where owner_id=p_owner and companion_id=(select companion_id from public.memory_jobs where request_id=p_request)
    and memory_key=candidate->>'key' and source_message_id=m.id and not user_edited;
 end loop;
 return result;
end; $$;

create or replace function public.morrow_claim_memory_job(p_owner text,p_request uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.memory_jobs;c public.companions;m public.messages;r public.turn_requests;previous text;
begin
 select * into j from public.memory_jobs where owner_id=p_owner and request_id=p_request for update;
 if not found or j.status in ('completed','suppressed') or j.attempts>=5 or (j.status='running' and j.lease_until>now()) then return jsonb_build_object('job',null); end if;
 select * into c from public.companions where id=j.companion_id and owner_id=p_owner;
 select * into m from public.messages where owner_id=p_owner and request_id=p_request and role='user';
 select * into r from public.turn_requests where owner_id=p_owner and id=p_request;
 if m.id is null or not c.memory_enabled or c.consent_version<>j.consent_version or m.created_at<=c.memory_reset_at then
   update public.memory_jobs set status='suppressed',updated_at=now() where request_id=p_request;
   return jsonb_build_object('job',null);
 end if;
 select left(content,1200) into previous from public.messages where owner_id=p_owner and conversation_id=m.conversation_id
  and role='assistant' and status='completed' and seq<m.seq order by seq desc limit 1;
 update public.memory_jobs set status='running',attempts=attempts+1,lease=gen_random_uuid(),lease_until=now()+interval '60 seconds',updated_at=now()
  where request_id=p_request returning * into j;
 return jsonb_build_object('job',to_jsonb(j),'source',jsonb_build_object('id',m.id,'content',m.content,
  'created_at',m.created_at,'timezone',r.context_timezone,'previous_assistant',previous));
end; $$;

create function public.morrow_current_routines(p_owner text,p_companion uuid,p_now timestamptz,p_timezone text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare t timestamp; minute integer; day integer; result jsonb;
begin
 if p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone) then return '[]'; end if;
 t=p_now at time zone p_timezone;minute=extract(hour from t)::integer*60+extract(minute from t)::integer;day=extract(dow from t)::integer;
 with valid as (
  select m.* from public.memories m join public.companions c on c.id=m.companion_id and c.owner_id=m.owner_id
   where m.owner_id=p_owner and m.companion_id=p_companion and c.memory_enabled and m.kind='routine'
    and m.verification not in ('unverified','superseded') and (m.expires_at is null or m.expires_at>p_now)
 ), applicable as (
  select r.*,d.anchor from valid r cross join (values(t::date),(t::date-1)) d(anchor)
   where (r.attributes->>'on_date'=d.anchor::text or (r.attributes->>'on_date' is null
    and coalesce(r.attributes->'weekdays','[]') @> to_jsonb(array[extract(dow from d.anchor)::integer])
    and not exists(select 1 from valid e where e.attributes->>'on_date'=d.anchor::text
      and coalesce(e.attributes->>'routine_kind',e.attributes->>'field')=coalesce(r.attributes->>'routine_kind',r.attributes->>'field'))))
   and (d.anchor=t::date or ((r.attributes->>'start_minute')::integer>(r.attributes->>'end_minute')::integer
    and minute<(r.attributes->>'end_minute')::integer))
 ) select coalesce(jsonb_agg(to_jsonb(r)),'[]') into result from (
  select id,left(content,600) as content,attributes,verification,anchor as schedule_date,
   case when coalesce((attributes->>'skip')::boolean,false) then false
    when attributes->>'start_minute' is null or attributes->>'end_minute' is null then false
    when (attributes->>'start_minute')::integer=(attributes->>'end_minute')::integer then false
    else t>=anchor::timestamp+make_interval(mins=>(attributes->>'start_minute')::integer)
     and t<anchor::timestamp+make_interval(mins=>(attributes->>'end_minute')::integer)
      +case when (attributes->>'start_minute')::integer>(attributes->>'end_minute')::integer then interval '1 day' else interval '0' end
    end as active_now
  from applicable order by active_now desc,case when attributes->>'routine_kind' in ('work','sleep') then 0 else 1 end,user_edited desc,updated_at desc limit 12
 )r;
 return result;
end; $$;

create function public.morrow_event_date(p_attributes jsonb,p_now timestamptz,p_timezone text)
returns date language plpgsql stable set search_path='' as $$
declare today date;candidate date;year integer;offset_year integer;
begin
 if p_attributes->>'annual' is distinct from 'true' then return (p_attributes->>'on_date')::date; end if;
 if p_timezone is null then return null; end if;
 today=(p_now at time zone p_timezone)::date;year=extract(year from today)::integer;
 for offset_year in 0..8 loop
  begin candidate=make_date(year+offset_year,(p_attributes->>'month')::integer,(p_attributes->>'day')::integer);
   exception when datetime_field_overflow then continue; end;
  if candidate>=today then return candidate; end if;
 end loop;
 return null;
end; $$;

create function public.morrow_companion_context(p_owner text,p_companion uuid,p_query text default '',p_conversation uuid default null,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.companions;p public.profiles;z text;local_time timestamp;today date;facts jsonb='[]';
 identity jsonb;old_discussions jsonb='[]';q tsquery;preferred text;language text;location text;
begin
 select * into c from public.companions where id=p_companion and owner_id=p_owner;
 if not found then raise exception 'not_found'; end if;
 if p_conversation is not null and not exists(select 1 from public.conversations where id=p_conversation and owner_id=p_owner and companion_id=p_companion) then raise exception 'not_found'; end if;
 select * into p from public.profiles where user_id=p_owner;
 z=coalesce(p.timezone,(select timezone from public.notification_preferences where owner_id=p_owner));
 preferred=p.preferred_name;language=p.language;location=p.general_location;
 if c.memory_enabled then
   if preferred is null then select attributes->>'value' into preferred from public.memories where owner_id=p_owner and companion_id=p_companion
    and kind='identity' and attributes->>'field'='preferred_name' and verification not in ('unverified','superseded')
    and (expires_at is null or expires_at>p_now) order by user_edited desc,updated_at desc limit 1; end if;
   if z is null then select attributes->>'value' into z from public.memories where owner_id=p_owner and companion_id=p_companion
    and kind='identity' and attributes->>'field'='timezone' and verification not in ('unverified','superseded')
    and (expires_at is null or expires_at>p_now) order by user_edited desc,updated_at desc limit 1; end if;
 end if;
 if z is not null and not exists(select 1 from pg_timezone_names where name=z) then z=null; end if;
 preferred=coalesce(preferred,p.display_name);
 if z is not null then local_time=p_now at time zone z;today=local_time::date; end if;
 if c.memory_enabled then
   q=websearch_to_tsquery('simple',left(p_query,2000));
   select coalesce(jsonb_agg(to_jsonb(f)-'kind_rank'),'[]') into facts from (
    select * from (
    select id,memory_key,category,kind,left(content,1200) as content,attributes,verification,temporal_status,
     source_message_id,source_quote,confidence,importance,created_at,updated_at,expires_at,
     public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) as event_date,
     case when kind<>'event' then null when temporal_status in ('cancelled','completed') then temporal_status
      when public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) is null or coalesce(attributes->>'timezone',z) is null then 'unresolved'
      when public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z))<(p_now at time zone coalesce(attributes->>'timezone',z))::date then 'past_planned'
      when public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z))=(p_now at time zone coalesce(attributes->>'timezone',z))::date then 'today'
      else 'upcoming' end as event_state,
     row_number() over(partition by kind order by
      (kind='event' and temporal_status not in ('completed','cancelled') and public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) between today-7 and today+30) desc nulls last,
      (kind='preference' and (category='communication_preferences' or memory_key like '%communication%')) desc,
      (search_vector @@ q) desc,user_edited desc,updated_at desc) as kind_rank,
     (ts_rank_cd(search_vector,q)+importance*.3)::real as relevance
    from public.memories m where owner_id=p_owner and companion_id=p_companion and verification<>'superseded'
     and (expires_at is null or expires_at>p_now)
     and not(kind='identity' and attributes->>'field'='preferred_name' and preferred is not null and attributes->>'value' is distinct from preferred)
     and not(kind='identity' and preferred is not null and attributes->>'field' is null and memory_key ~ '(name|nickname)')
    ) ranked where kind_rank<=case when kind='event' then 6 when kind='routine' then 5 else 4 end
    order by case when kind_rank=1 and kind='identity' then 0 when kind_rank=1 and kind='routine' then 1
     when kind='event' and (public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) is null or public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) between today-7 and today+30) then 2
     else 3 end, relevance desc,updated_at desc limit 32
   )f;
   select coalesce(jsonb_agg(to_jsonb(d)),'[]') into old_discussions from (
    select m.conversation_id,v.title,m.role,left(m.content,700) as content,m.created_at from public.messages m
     join public.conversations v on v.id=m.conversation_id and v.owner_id=m.owner_id
    where m.owner_id=p_owner and v.companion_id=p_companion and m.status='completed'
     and (p_conversation is null or m.conversation_id<>p_conversation)
     and (c.conversation_retention_days is null or v.updated_at>p_now-make_interval(days=>c.conversation_retention_days))
    order by m.created_at desc,m.seq desc limit 6
   )d;
 end if;
 identity=jsonb_build_object('preferred_name',preferred,'full_name',p.display_name,'language',language,'general_location',location,
  'source',case when p.preferred_name is not null or (preferred=p.display_name) then 'explicit_profile' else 'active_memory' end);
 return jsonb_build_object('identity',identity,'clock',jsonb_build_object('utc',p_now,'timezone',z,'local',local_time,'local_date',today),
  'first_meeting',jsonb_build_object('introduced',c.introduced_at is not null,'name_question_asked',c.name_question_asked_at is not null),
  'memories',facts,'current_routine',public.morrow_current_routines(p_owner,p_companion,p_now,z),'previous_discussions',old_discussions);
end; $$;

create function public.morrow_begin_greeting(p_owner text,p_conversation uuid,p_request uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v public.conversations;c public.companions;r public.turn_requests;h jsonb;ctx jsonb;t text;
begin
 select * into v from public.conversations where id=p_conversation and owner_id=p_owner for update;
 if not found then raise exception 'not_found'; end if;
 select * into c from public.companions where id=v.companion_id and owner_id=p_owner;
 select * into r from public.turn_requests where conversation_id=v.id and owner_id=p_owner and kind='greeting' for update;
 if found and r.status='completed' then
  select content into t from public.messages where owner_id=p_owner and request_id=r.id and role='assistant';
  return jsonb_build_object('status','completed','text',t,'request_id',r.id);
 end if;
 if r.id is not null and r.status='running' and r.lease_until>now() then raise exception 'turn_busy'; end if;
 if exists(select 1 from public.messages where owner_id=p_owner and conversation_id=v.id and role='user') then raise exception 'conversation_started'; end if;
 if v.active_request_id is not null and v.active_until>now() then raise exception 'turn_busy'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 if r.id is null and (select count(*) from public.turn_requests where owner_id=p_owner and created_at>now()-interval '1 minute')>=10 then raise exception 'rate_limited'; end if;
 ctx=public.morrow_companion_context(p_owner,c.id,'',v.id);
 if r.id is null then
  insert into public.turn_requests(id,owner_id,conversation_id,status,lease_until,consent_version,kind,greeting_asks_name)
   values(p_request,p_owner,v.id,'running',now()+interval '120 seconds',c.consent_version,'greeting',
    c.name_question_asked_at is null and ctx->'identity'->>'preferred_name' is null) returning * into r;
 else update public.turn_requests set status='running',lease=gen_random_uuid(),lease_until=now()+interval '120 seconds',updated_at=now() where id=r.id returning * into r; end if;
 insert into public.messages(owner_id,conversation_id,request_id,role,content,status) values(p_owner,v.id,r.id,'assistant','','pending')
  on conflict(request_id,role) do update set content='',status='pending';
 update public.conversations set active_request_id=r.id,active_until=r.lease_until where id=v.id;
 return jsonb_build_object('status','running','lease',r.lease,'request_id',r.id,'companion',to_jsonb(c),'history','[]'::jsonb,'consent_version',r.consent_version);
end; $$;

create or replace function public.morrow_enqueue_memory() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.kind<>'user' then return new; end if;
 insert into public.memory_jobs(request_id,owner_id,companion_id,consent_version)
  select new.id,new.owner_id,c.id,new.consent_version from public.conversations v join public.companions c on c.id=v.companion_id and c.owner_id=new.owner_id
  where v.id=new.conversation_id and c.memory_enabled and c.consent_version=new.consent_version on conflict do nothing;
 return new;
end; $$;
create function public.morrow_introduction_completed() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.status='completed' and old.status is distinct from 'completed' then
  update public.companions set introduced_at=coalesce(introduced_at,now()),
   name_question_asked_at=case when new.greeting_asks_name then coalesce(name_question_asked_at,now()) else name_question_asked_at end
   where owner_id=new.owner_id and id=(select companion_id from public.conversations where id=new.conversation_id and owner_id=new.owner_id);
 end if;
 return new;
end; $$;
create trigger record_introduction after update of status on public.turn_requests for each row execute function public.morrow_introduction_completed();
-- Greeting/proactive turns must not become inferred interaction observations.
drop trigger observe_completed_turn on public.turn_requests;
create trigger observe_completed_turn after update of status on public.turn_requests for each row when(new.kind='user') execute function public.morrow_observe_turn();

-- Structured metadata is included in the existing memory manager/export shape.
create or replace function public.morrow_messages(p_owner text,p_conversation uuid,p_before bigint default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.conversations where owner_id=p_owner and id=p_conversation) then raise exception 'not_found'; end if;
 select coalesce(jsonb_agg(to_jsonb(m) order by seq),'[]') into result from (
  select m.id,m.seq,m.request_id,m.role,m.content,m.created_at,r.kind,
   case when m.status='pending' and r.lease_until<now() then 'failed' else m.status end as status
   from public.messages m join public.turn_requests r on r.id=m.request_id and r.owner_id=m.owner_id
   where m.owner_id=p_owner and m.conversation_id=p_conversation and (p_before is null or m.seq<p_before)
   order by m.seq desc limit 50)m;
 return jsonb_build_object('messages',result);
end; $$;

create or replace function public.morrow_list_memories(p_owner text,p_companion uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;total integer;
begin
 if not exists(select 1 from public.companions where id=p_companion and owner_id=p_owner) then raise exception 'not_found'; end if;
 delete from public.memories where owner_id=p_owner and expires_at<=now();
 select count(*) into total from public.memories where owner_id=p_owner and companion_id=p_companion;
 select coalesce(jsonb_agg(to_jsonb(m)-'search_vector'),'[]') into result from (
  select * from public.memories where owner_id=p_owner and companion_id=p_companion order by updated_at desc limit 100)m;
 return jsonb_build_object('memories',result,'total',total,'pending_count',(select count(*) from public.memory_jobs where owner_id=p_owner and companion_id=p_companion and status in ('pending','running','failed') and attempts<5));
end; $$;
do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
 'morrow_memory_kind','morrow_save_personal_profile','morrow_snapshot_context','morrow_normalize_attributes',
 'morrow_clear_stale_attributes','morrow_save_structured_memory','morrow_apply_companion_memory_job',
 'morrow_companion_context','morrow_begin_greeting','morrow_introduction_completed','morrow_current_routines','morrow_event_date') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
-- END 202611030010_companion_continuity.sql

-- BEGIN 202611030011_personal_proactivity.sql
-- Additive candidate: retains the existing queue, leases, RLS and export/erasure paths.
alter table public.notification_preferences add column additional_minutes integer[] not null default '{}',
 add column max_per_day integer not null default 1 check(max_per_day between 1 and 3);
alter table public.scheduled_checkins add column slot_minute integer,
 add column reason text check(length(reason)<=2000), add column source_memory_id uuid,
 add column requires_memory boolean not null default false,
 add column conversation_id uuid,
 add column provider_accepted_at timestamptz, add column received_at timestamptz, add column opened_at timestamptz,
 add column outcome_detail text;
alter table public.memories add unique(owner_id,id);
alter table public.scheduled_checkins add foreign key(owner_id,source_memory_id) references public.memories(owner_id,id) on delete set null(source_memory_id),
 add foreign key(owner_id,conversation_id) references public.conversations(owner_id,id) on delete set null(conversation_id);
alter table public.scheduled_checkins add column source_updated_at timestamptz;
alter table public.scheduled_checkins add column prepared_profile_at timestamptz;
alter table public.scheduled_checkins add column reminder_request_id uuid,
 add column reminder_local timestamp,add column reminder_timezone text;
create unique index reminder_request_once on public.scheduled_checkins(owner_id,reminder_request_id) where reminder_request_id is not null;
drop index public.one_daily_checkin;
create unique index recurring_checkin_slot on public.scheduled_checkins(owner_id,local_date,slot_minute)
 where kind='checkin' and local_date is not null;

create function public.morrow_save_personal_schedule(p_owner text,p_companion uuid,
 p_checkins boolean,p_suggestions boolean,p_birthdays boolean,p_timezone text,p_local_minute integer,
 p_weekdays integer[],p_quiet_start integer,p_quiet_end integer,p_additional integer[],p_max integer)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_max not between 1 and 3 or p_additional is null or cardinality(p_additional)>2
  or cardinality(p_additional)+1>p_max or exists(select 1 from unnest(p_additional) m
   where m not between 0 and 1439 or m=p_local_minute or ((p_checkins or p_suggestions or p_birthdays) and public.morrow_is_quiet(m,p_quiet_start,p_quiet_end)))
  or (select count(distinct m) from unnest(p_additional) m)<>cardinality(p_additional) then raise exception 'invalid_input'; end if;
 perform public.morrow_save_notification_preferences(p_owner,p_companion,p_checkins,p_suggestions,p_birthdays,
  p_timezone,p_local_minute,p_weekdays,p_quiet_start,p_quiet_end);
 update public.notification_preferences set additional_minutes=p_additional,max_per_day=p_max where owner_id=p_owner;
 return public.morrow_notification_preferences(p_owner);
end; $$;

create function public.morrow_profile_timezone_changed() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.timezone is not null and new.timezone is distinct from old.timezone then
  update public.notification_preferences set timezone=new.timezone,revision=revision+1,updated_at=now()
   where owner_id=new.user_id and timezone is distinct from new.timezone;
  if found then update public.scheduled_checkins set status='suppressed',outcome_detail='Timezone changed; confirm a new reminder time.'
   where owner_id=new.user_id and status in ('queued','sending'); end if;
 end if;
 return new;
end; $$;
create trigger sync_profile_timezone after update of timezone on public.profiles for each row execute function public.morrow_profile_timezone_changed();

create function public.morrow_routine_blocks(p_owner text,p_companion uuid,p_now timestamptz,p_zone text)
returns boolean language sql security invoker set search_path='' as $$
 select exists(select 1 from jsonb_array_elements(public.morrow_current_routines(p_owner,p_companion,p_now,p_zone)) r
  where (r->>'active_now')::boolean and coalesce((r->'attributes'->>'block_notifications')::boolean,
    r->'attributes'->>'routine_kind' in ('work','sleep'),false));
$$;

-- Explicit reminder confirmation; ambiguous/nonexistent local wall times are rejected.
create function public.morrow_schedule_personal_reminder(p_owner text,p_kind text,p_local timestamp,p_zone text,
 p_reason text,p_conversation uuid default null,p_source uuid default null,p_request uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare due timestamptz;result jsonb;p public.notification_preferences;previous public.scheduled_checkins;
begin
 select * into p from public.notification_preferences where owner_id=p_owner for update;
 if p_request is not null then
  select * into previous from public.scheduled_checkins where owner_id=p_owner and reminder_request_id=p_request;
  if found then
   if previous.reminder_local is distinct from p_local or previous.reminder_timezone is distinct from p_zone
    or previous.reason is distinct from btrim(p_reason) or previous.source_memory_id is distinct from p_source
    or previous.conversation_id is distinct from p_conversation then raise exception 'request_conflict'; end if;
   return jsonb_build_object('checkin',to_jsonb(previous)-'lease'-'lease_until');
  end if;
 end if;
 if p.owner_id is null or p_zone is distinct from p.timezone or length(btrim(p_reason)) not between 1 and 2000
  or not exists(select 1 from pg_timezone_names where name=p_zone) then raise exception 'invalid_input'; end if;
 due=p_local at time zone p_zone;
 if due at time zone p_zone<>p_local or exists(select 1 from generate_series(-120,120) n
  where n<>0 and (due+make_interval(mins=>n)) at time zone p_zone=p_local) then raise exception 'ambiguous_local_time'; end if;
 if public.morrow_is_quiet(extract(hour from p_local)::integer*60+extract(minute from p_local)::integer,p.quiet_start,p.quiet_end)
  or not extract(dow from p_local)::integer=any(p.weekdays)
  or public.morrow_routine_blocks(p_owner,p.companion_id,due,p_zone) then raise exception 'outside_notification_hours'; end if;
 if p_conversation is not null and not exists(select 1 from public.conversations where id=p_conversation and owner_id=p_owner and companion_id=p.companion_id) then raise exception 'not_found'; end if;
 if p_source is not null and not exists(select 1 from public.memories where id=p_source and owner_id=p_owner and companion_id=p.companion_id) then raise exception 'not_found'; end if;
 result=public.morrow_schedule_followup(p_owner,p_kind,due);
 update public.scheduled_checkins set reason=btrim(p_reason),conversation_id=p_conversation,source_memory_id=p_source,
  source_updated_at=(select updated_at from public.memories where id=p_source and owner_id=p_owner),
  reminder_request_id=p_request,reminder_local=p_local,reminder_timezone=p_zone,
  requires_memory=p_source is not null where id=(result->'checkin'->>'id')::uuid;
 return jsonb_build_object('checkin',(select to_jsonb(j)-'lease'-'lease_until' from public.scheduled_checkins j where id=(result->'checkin'->>'id')::uuid));
end; $$;

create or replace function public.morrow_due_checkins(p_now timestamptz default now(),p_limit integer default 20)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare p public.notification_preferences;t timestamp;minute integer;slot integer;job public.scheduled_checkins;
 result jsonb='[]';devices jsonb;fact public.memories;checkin_reason text;
begin
 update public.scheduled_checkins set status='unknown',outcome_detail='Worker lease expired; delivery unconfirmed.' where status='sending' and lease_until<p_now;
 update public.scheduled_checkins set status='suppressed',outcome_detail='Expired before dispatch.' where status='queued' and due_at<p_now-interval '1 day';
 for p in select * from public.notification_preferences where timezone is not null
  and (checkins_enabled or suggestions_enabled or birthdays_enabled) order by owner_id for update skip locked loop
  t=p_now at time zone p.timezone;minute=extract(hour from t)::integer*60+extract(minute from t)::integer;
  if public.morrow_is_quiet(minute,p.quiet_start,p.quiet_end) or not extract(dow from t)::integer=any(p.weekdays)
   or public.morrow_routine_blocks(p.owner_id,p.companion_id,p_now,p.timezone) then continue; end if;
  if not exists(select 1 from public.device_tokens where owner_id=p.owner_id and updated_at>p_now-interval '90 days') then continue; end if;
  if (select count(*) from public.scheduled_checkins where owner_id=p.owner_id and local_date=t::date and status<>'queued')>=p.max_per_day then continue; end if;
  foreach slot in array array_prepend(p.local_minute,p.additional_minutes) loop
   if (p.checkins_enabled or p.suggestions_enabled) and minute>=slot and minute<slot+60
    and not exists(select 1 from public.scheduled_checkins where owner_id=p.owner_id and kind='checkin' and local_date=t::date and slot_minute=slot) then
    fact=null;
    select m.* into fact from public.memories m join public.companions c on c.id=m.companion_id and c.owner_id=m.owner_id
     where m.owner_id=p.owner_id and m.companion_id=p.companion_id and c.memory_enabled
      and m.verification not in ('unverified','superseded') and (m.expires_at is null or m.expires_at>p_now)
      and ((m.kind='event' and m.temporal_status not in ('completed','cancelled')
        and public.morrow_event_date(m.attributes,p_now,coalesce(m.attributes->>'timezone',p.timezone)) between t::date-3 and t::date+1)
       or (m.kind='routine' and coalesce(m.attributes->'weekdays','[]') @> to_jsonb(array[extract(dow from t)::integer]) and not coalesce((m.attributes->>'skip')::boolean,false))
       or (m.kind='development' and m.updated_at>p_now-interval '14 days'))
     order by case when m.kind='event' then 0 when m.kind='routine' then 1 else 2 end,m.updated_at desc limit 1;
    if not p.checkins_enabled and fact.id is null then continue; end if;
    checkin_reason=case when fact.id is null then 'User requested a recurring check-in at this local time.'
     else 'User enabled contextual check-ins. Relevant user-stated detail: '||left(fact.content,1000)||
      case when fact.kind='event' then ' Event date: '||coalesce(public.morrow_event_date(fact.attributes,p_now,coalesce(fact.attributes->>'timezone',p.timezone))::text,'unresolved')||'. Planned events are not proof they happened.' else '' end end;
    insert into public.scheduled_checkins(owner_id,kind,due_at,local_date,slot_minute,preference_revision,reason,source_memory_id,source_updated_at,requires_memory)
     values(p.owner_id,'checkin',p_now,t::date,slot,p.revision,checkin_reason,fact.id,fact.updated_at,fact.id is not null) on conflict do nothing;
   end if;
  end loop;
  select * into job from public.scheduled_checkins where owner_id=p.owner_id and status='queued' and due_at<=p_now and preference_revision=p.revision
   and ((kind='checkin' and (p.checkins_enabled or p.suggestions_enabled)) or (kind='followup' and p.checkins_enabled) or (kind='important_date' and p.birthdays_enabled))
   order by case when kind='checkin' then 1 else 0 end,due_at,id limit 1 for update;
  if not found then continue; end if;
  update public.scheduled_checkins set status='sending',local_date=t::date,lease=gen_random_uuid(),lease_until=p_now+interval '2 minutes',
   reason=coalesce(reason,'User explicitly scheduled this reminder.') where id=job.id returning * into job;
  select jsonb_agg(jsonb_build_object('installation_id',installation_id,'token',token)) into devices from public.device_tokens where owner_id=p.owner_id and updated_at>p_now-interval '90 days';
  result=result||jsonb_build_array(jsonb_build_object('id',job.id,'lease',job.lease,'owner_id',job.owner_id,'companion_id',p.companion_id,'reason',job.reason,'devices',devices));
  exit when jsonb_array_length(result)>=least(greatest(p_limit,1),100);
 end loop;
 return jsonb_build_object('jobs',result);
end; $$;

create function public.morrow_checkin_permission(p_id uuid,p_lease uuid,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.scheduled_checkins;p public.notification_preferences;ttl integer;minute integer;r jsonb;start_seconds integer;seconds integer;
begin
 select * into j from public.scheduled_checkins where id=p_id and lease=p_lease and status='sending' and lease_until>p_now;
 if not found then return jsonb_build_object('allowed',false,'ttl_seconds',0); end if;
 select * into p from public.notification_preferences where owner_id=j.owner_id;
 if p.timezone is null or j.preference_revision<>p.revision
  or (j.prepared_profile_at is not null and j.prepared_profile_at is distinct from (select updated_at from public.profiles where user_id=j.owner_id))
  or exists(select 1 from public.turn_requests r join public.conversations v on v.id=r.conversation_id and v.owner_id=r.owner_id
   join public.companions c on c.id=v.companion_id and c.owner_id=r.owner_id where r.id=j.id and r.owner_id=j.owner_id and r.consent_version<>c.consent_version)
  or not((j.kind='checkin' and (p.checkins_enabled or p.suggestions_enabled)) or (j.kind='followup' and p.checkins_enabled) or (j.kind='important_date' and p.birthdays_enabled))
  or (j.requires_memory and not exists(select 1 from public.memories m join public.companions c on c.id=m.companion_id and c.owner_id=m.owner_id
   where m.id=j.source_memory_id and m.owner_id=j.owner_id and m.updated_at=j.source_updated_at and c.memory_enabled and m.verification not in ('unverified','superseded')
    and m.temporal_status not in ('completed','cancelled') and (m.expires_at is null or m.expires_at>p_now)))
  or (j.conversation_id is not null and not exists(select 1 from public.conversations where id=j.conversation_id and owner_id=j.owner_id)) then return jsonb_build_object('allowed',false,'ttl_seconds',0); end if;
 minute=extract(hour from p_now at time zone p.timezone)::integer*60+extract(minute from p_now at time zone p.timezone)::integer;
 if public.morrow_is_quiet(minute,p.quiet_start,p.quiet_end) or not extract(dow from p_now at time zone p.timezone)::integer=any(p.weekdays)
  or public.morrow_routine_blocks(j.owner_id,p.companion_id,p_now,p.timezone) then return jsonb_build_object('allowed',false,'ttl_seconds',0); end if;
 ttl=public.morrow_notification_ttl(p_now,p.timezone,p.quiet_start,p.quiet_end);
 seconds=floor(extract(epoch from (p_now at time zone p.timezone)::time))::integer;
 ttl=least(ttl,86400-seconds);
 for r in select value from jsonb_array_elements(public.morrow_current_routines(j.owner_id,p.companion_id,p_now,p.timezone)) loop
  if coalesce((r->'attributes'->>'block_notifications')::boolean,r->'attributes'->>'routine_kind' in ('work','sleep'),false)
   and not coalesce((r->'attributes'->>'skip')::boolean,false) and r->'attributes'->>'start_minute' is not null
   and (r->'attributes'->>'on_date'=(p_now at time zone p.timezone)::date::text or coalesce(r->'attributes'->'weekdays','[]') @> to_jsonb(array[extract(dow from p_now at time zone p.timezone)::integer])) then
    start_seconds=(r->'attributes'->>'start_minute')::integer*60-seconds;
    if start_seconds>=0 then ttl=least(ttl,start_seconds); end if;
  end if;
 end loop;
 return jsonb_build_object('allowed',ttl>0,'ttl_seconds',ttl);
end; $$;
create or replace function public.morrow_authorize_checkin(p_id uuid,p_lease uuid)
returns jsonb language sql security invoker set search_path='' as $$ select public.morrow_checkin_permission(p_id,p_lease,now()); $$;

create or replace function public.morrow_finish_checkin(p_id uuid,p_lease uuid,p_status text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_status not in ('sent','failed','unknown','suppressed') then raise exception 'invalid_input'; end if;
 update public.scheduled_checkins set status=p_status,provider_accepted_at=case when p_status='sent' then now() else provider_accepted_at end,
  outcome_detail=case p_status when 'sent' then 'Accepted by push provider; device delivery unconfirmed.' when 'unknown' then 'Provider result unconfirmed; not automatically resent.'
   when 'suppressed' then 'Preferences, source, routine, or quiet hours prevented dispatch.' else 'Dispatch failed.' end
  where id=p_id and lease=p_lease and status='sending';
 return jsonb_build_object('ok',true);
end; $$;
create or replace function public.morrow_cancel_checkin(p_owner text,p_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 update public.scheduled_checkins set status='suppressed',outcome_detail='Cancelled by you.' where owner_id=p_owner and id=p_id and status in ('queued','sending');
 return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_checkin_history(p_owner text) returns jsonb language sql security invoker set search_path='' as $$
 select jsonb_build_object('checkins',coalesce((select jsonb_agg(to_jsonb(j)-'lease'-'lease_until') from
  (select * from public.scheduled_checkins where owner_id=p_owner order by created_at desc,id desc limit 100)j),'[]'));
$$;
create function public.morrow_checkin_receipt(p_owner text,p_id uuid,p_opened boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 update public.scheduled_checkins set received_at=coalesce(received_at,now()),opened_at=case when p_opened then coalesce(opened_at,now()) else opened_at end
  where id=p_id and owner_id=p_owner and status in ('sent','sending','unknown');
 return jsonb_build_object('conversation',(select to_jsonb(v) from public.scheduled_checkins j join public.conversations v on v.id=j.conversation_id and v.owner_id=j.owner_id where j.id=p_id and j.owner_id=p_owner));
end; $$;

alter function public.morrow_companion_context(text,uuid,text,uuid,timestamptz) rename to morrow_companion_context_core;
create function public.morrow_companion_context(p_owner text,p_companion uuid,p_query text default '',p_conversation uuid default null,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;records jsonb;
begin
 result=public.morrow_companion_context_core(p_owner,p_companion,p_query,p_conversation,p_now);
 select coalesce(jsonb_agg(to_jsonb(j)),'[]') into records from (
  select s.kind,s.due_at,s.status,s.provider_accepted_at,s.received_at,s.opened_at,left(s.reason,240) as reason
   from public.scheduled_checkins s join public.notification_preferences p on p.owner_id=s.owner_id
   join public.companions c on c.id=p.companion_id and c.owner_id=p.owner_id
   where s.owner_id=p_owner and c.id=p_companion and (not s.requires_memory or (c.memory_enabled and exists(
    select 1 from public.memories m where m.id=s.source_memory_id and m.owner_id=p_owner and m.updated_at=s.source_updated_at
     and m.verification not in ('unverified','superseded') and m.temporal_status not in ('completed','cancelled') and (m.expires_at is null or m.expires_at>p_now))))
    and s.created_at>p_now-interval '7 days' order by s.created_at desc limit 5)j;
 return result||jsonb_build_object('notification_records',records);
end; $$;

-- One durable assistant turn per queue item, using the normal completion path.
create function public.morrow_begin_proactive(p_owner text,p_id uuid,p_lease uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.scheduled_checkins;p public.notification_preferences;c public.companions;v public.conversations;r public.turn_requests;t text;h jsonb;
begin
 select * into j from public.scheduled_checkins where owner_id=p_owner and id=p_id and lease=p_lease for update;
 if not found or not (public.morrow_authorize_checkin(p_id,p_lease)->>'allowed')::boolean then raise exception 'not_found'; end if;
 select * into p from public.notification_preferences where owner_id=p_owner;
 select * into c from public.companions where owner_id=p_owner and id=p.companion_id;
 select * into r from public.turn_requests where id=j.id and owner_id=p_owner;
 if found and r.status='completed' then return jsonb_build_object('status','completed','conversation_id',j.conversation_id); end if;
 if j.conversation_id is null then
  insert into public.conversations(owner_id,companion_id,title) values(p_owner,c.id,'A check-in') returning * into v;
  update public.scheduled_checkins set conversation_id=v.id where id=j.id;
 else select * into v from public.conversations where id=j.conversation_id and owner_id=p_owner for update; end if;
 if v.id is null then raise exception 'not_found'; end if;
 if v.active_request_id is not null and v.active_until>now() then raise exception 'turn_busy'; end if;
 if r.id is null then
  insert into public.turn_requests(id,owner_id,conversation_id,status,lease_until,consent_version,kind)
   values(j.id,p_owner,v.id,'running',now()+interval '90 seconds',c.consent_version,'proactive') returning * into r;
 else update public.turn_requests set status='running',lease=gen_random_uuid(),lease_until=now()+interval '90 seconds' where id=r.id returning * into r; end if;
 insert into public.messages(owner_id,conversation_id,request_id,role,content,status) values(p_owner,v.id,r.id,'assistant','','pending')
  on conflict(request_id,role) do update set content='',status='pending';
 update public.conversations set active_request_id=r.id,active_until=r.lease_until where id=v.id;
 update public.scheduled_checkins set prepared_profile_at=(select updated_at from public.profiles where user_id=p_owner) where id=j.id;
 select coalesce(jsonb_agg(to_jsonb(m) order by seq),'[]') into h from (
  select role,content,seq from public.messages where owner_id=p_owner and conversation_id=v.id and status='completed' order by seq desc limit 18)m;
 return jsonb_build_object('status','running','lease',r.lease,'request_id',r.id,'conversation_id',v.id,'companion',to_jsonb(c),'reason',j.reason,'history',h);
end; $$;

create function public.morrow_cancel_conversation_checkins() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 update public.scheduled_checkins set status='suppressed',outcome_detail='The conversation was removed.'
  where owner_id=old.owner_id and conversation_id=old.id and status in ('queued','sending');
 return old;
end; $$;
create trigger cancel_conversation_checkins before delete on public.conversations for each row execute function public.morrow_cancel_conversation_checkins();

do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
 'morrow_save_personal_schedule','morrow_routine_blocks','morrow_schedule_personal_reminder','morrow_checkin_permission',
 'morrow_checkin_history','morrow_checkin_receipt','morrow_begin_proactive','morrow_profile_timezone_changed','morrow_companion_context','morrow_cancel_conversation_checkins') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
-- END 202611030011_personal_proactivity.sql

-- BEGIN 202611030012_account_names.sql
-- Local additive candidate; reconcile target migrations before deployment.
alter table public.profiles add column username text
 check(username is null or username ~ '^[a-z0-9][a-z0-9_]{2,29}$');
create unique index unique_profile_username on public.profiles(lower(username)) where username is not null;

create function public.morrow_save_named_profile(p_owner text,p_username text,p_preferred_name text,p_display_name text,
 p_timezone text,p_language text,p_location text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;handle text=nullif(lower(btrim(p_username)),'');
begin
 if handle is not null and handle !~ '^[a-z0-9][a-z0-9_]{2,29}$' then raise exception 'invalid_username'; end if;
 if handle is not null and (p_preferred_name is null or length(btrim(p_preferred_name)) not between 1 and 80) then raise exception 'invalid_input'; end if;
 perform public.morrow_save_personal_profile(p_owner,p_preferred_name,p_display_name,p_timezone,p_language,p_location);
 update public.profiles set username=handle where user_id=p_owner returning to_jsonb(profiles.*) into result;
 return jsonb_build_object('profile',result);
exception when unique_violation then raise exception 'username_taken';
end; $$;
revoke all on function public.morrow_save_named_profile(text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.morrow_save_named_profile(text,text,text,text,text,text,text) to service_role;
-- END 202611030012_account_names.sql

-- BEGIN 202611030013_require_sign_in.sql
-- Registered Firebase accounts are required for every client read policy.
-- Existing guest data is retained so its account can still be linked at signup.
create or replace function public.morrow_authenticated_owner() returns text
language sql stable security definer set search_path='' as $$
select case when (auth.jwt()->>'iss')='https://securetoken.google.com/'||c.firebase_project_id
 and (auth.jwt()->'firebase'->>'tenant') is null
 and coalesce(auth.jwt()->'firebase'->>'sign_in_provider','') not in ('','anonymous')
 and not exists(select 1 from public.account_deletions d where d.owner_id=auth.jwt()->>'sub')
 then auth.jwt()->>'sub' else null end from public.identity_configuration c where c.singleton;
$$;
revoke all on function public.morrow_authenticated_owner() from public,anon;
grant execute on function public.morrow_authenticated_owner() to authenticated,service_role;
notify pgrst,'reload schema';
-- END 202611030013_require_sign_in.sql

-- BEGIN 202611030014_personal_introduction.sql
-- Additive: keep existing profiles, account ownership and consent machinery.
alter table public.profiles add column age_group text
 check(age_group is null or age_group in ('18_24','25_34','35_44','45_54','55_plus')),
 add column introduction_completed_at timestamptz,
 add column welcome_completed_at timestamptz;

-- Existing companions must not be forced through a first-meeting replay.
update public.profiles p set introduction_completed_at=now(),welcome_completed_at=now()
 where exists(select 1 from public.companions c where c.owner_id=p.user_id);

create function public.morrow_save_introduction(p_owner text,p_age_group text,p_language text,p_timezone text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if p_age_group is null or p_age_group not in ('18_24','25_34','35_44','45_54','55_plus')
  or p_language is null or length(btrim(p_language)) not between 1 and 40
  or p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone)
 then raise exception 'invalid_input'; end if;
 update public.profiles set age_group=p_age_group,language=btrim(p_language),timezone=p_timezone,
  introduction_completed_at=coalesce(introduction_completed_at,now()),updated_at=now()
  where user_id=p_owner and username is not null and preferred_name is not null
  returning to_jsonb(profiles.*) into result;
 if result is null then raise exception 'invalid_input'; end if;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_require_eligible(p_owner text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where user_id=p_owner and introduction_completed_at is not null
   and age_group in ('18_24','25_34','35_44','45_54','55_plus')) then raise exception 'introduction_required'; end if;
 return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_complete_welcome(p_owner text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 update public.profiles set welcome_completed_at=coalesce(welcome_completed_at,now()),updated_at=now()
  where user_id=p_owner and introduction_completed_at is not null
   and exists(select 1 from public.companions c where c.owner_id=p_owner)
  returning to_jsonb(profiles.*) into result;
 if result is null then raise exception 'invalid_input'; end if;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_personal_context(p_owner text,p_companion uuid,p_query text default '',p_conversation uuid default null,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;age text;
begin
 result=public.morrow_companion_context(p_owner,p_companion,p_query,p_conversation,p_now);
 select age_group into age from public.profiles where user_id=p_owner;
 return jsonb_set(result,'{identity,age_group}',coalesce(to_jsonb(age),'null'));
end; $$;

create function public.morrow_home_summary(p_owner text,p_companion uuid,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path='' as $$
declare ctx jsonb;reminders jsonb;events jsonb;last_message timestamptz;
begin
 ctx=public.morrow_personal_context(p_owner,p_companion,'',null,p_now);
 select max(m.created_at) into last_message from public.messages m
  join public.conversations c on c.id=m.conversation_id and c.owner_id=m.owner_id
  where m.owner_id=p_owner and c.companion_id=p_companion and m.role='user' and m.status='completed';
 select coalesce(jsonb_agg(to_jsonb(r)),'[]') into reminders from (
  select s.id,s.kind,s.reason,s.due_at,s.status,
   to_char(s.due_at at time zone p.timezone,'YYYY-MM-DD"T"HH24:MI:SS') as local_time,p.timezone
   from public.scheduled_checkins s
   join public.notification_preferences p on p.owner_id=s.owner_id and p.revision=s.preference_revision
   where s.owner_id=p_owner and p.companion_id=p_companion and s.kind in ('followup','important_date')
    and s.status in ('queued','sending') and s.due_at>=p_now
   order by s.due_at limit 3
 )r;
 select coalesce(jsonb_agg(e),'[]') into events from (
  select jsonb_build_object('id',m->>'id','content',m->>'content','date',m->>'event_date') e
  from jsonb_array_elements(ctx->'memories') m where m->>'kind'='event'
   and m->>'verification' not in ('unverified','superseded') and m->>'event_state' in ('today','upcoming')
   order by m->>'event_date' limit 3
 )f;
 return jsonb_build_object('clock',ctx->'clock','last_user_message_at',last_message,
  'reminders',reminders,'events',events);
end; $$;

do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
  'morrow_save_introduction','morrow_complete_welcome','morrow_personal_context','morrow_home_summary','morrow_require_eligible') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
-- END 202611030014_personal_introduction.sql

-- BEGIN 202611030015_inactivity_checkins.sql
-- Existing explicitly scheduled check-ins retain their cadence (0). New UI
-- preferences default to two days of inactivity and stop after one unanswered check-in.
alter table public.notification_preferences add column inactivity_days integer not null default 0
 check(inactivity_days between 0 and 14);

create function public.morrow_save_friend_schedule(p_owner text,p_companion uuid,
 p_checkins boolean,p_suggestions boolean,p_birthdays boolean,p_timezone text,p_local_minute integer,
 p_weekdays integer[],p_quiet_start integer,p_quiet_end integer,p_additional integer[],p_max integer,p_inactivity_days integer)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_inactivity_days is null or p_inactivity_days not between 0 and 14 then raise exception 'invalid_input'; end if;
 perform public.morrow_save_personal_schedule(p_owner,p_companion,p_checkins,p_suggestions,p_birthdays,p_timezone,
  p_local_minute,p_weekdays,p_quiet_start,p_quiet_end,p_additional,p_max);
 update public.notification_preferences set inactivity_days=p_inactivity_days where owner_id=p_owner;
 return public.morrow_notification_preferences(p_owner);
end; $$;

create function public.morrow_inactivity_allowed(p_owner text,p_companion uuid,p_now timestamptz,p_days integer,p_exclude uuid default null)
returns boolean language plpgsql stable security invoker set search_path='' as $$
declare anchor timestamptz;
begin
 if p_days=0 then return true; end if;
 select max(m.created_at) into anchor from public.messages m join public.conversations c
  on c.id=m.conversation_id and c.owner_id=m.owner_id
  where m.owner_id=p_owner and c.companion_id=p_companion and m.role='user' and m.status='completed';
 anchor=coalesce(anchor,(select created_at from public.profiles where user_id=p_owner));
 if anchor is null or anchor>p_now-make_interval(days=>p_days) then return false; end if;
 return not exists(select 1 from public.scheduled_checkins where owner_id=p_owner and kind='checkin'
  and status in ('sending','sent','unknown') and created_at>=anchor and (p_exclude is null or id<>p_exclude));
end; $$;

alter function public.morrow_checkin_permission(uuid,uuid,timestamptz) rename to morrow_checkin_permission_core;
create function public.morrow_checkin_permission(p_id uuid,p_lease uuid,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.scheduled_checkins;p public.notification_preferences;
begin
 select * into j from public.scheduled_checkins where id=p_id and lease=p_lease;
 select * into p from public.notification_preferences where owner_id=j.owner_id;
 if j.kind='checkin' and not public.morrow_inactivity_allowed(j.owner_id,p.companion_id,p_now,p.inactivity_days,j.id)
 then return jsonb_build_object('allowed',false,'ttl_seconds',0); end if;
 return public.morrow_checkin_permission_core(p_id,p_lease,p_now);
end; $$;

do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
  'morrow_save_friend_schedule','morrow_inactivity_allowed','morrow_checkin_permission','morrow_checkin_permission_core') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;

-- Preserve the existing queue, routine guards, leases and reminder priority.
create or replace function public.morrow_due_checkins(p_now timestamptz default now(),p_limit integer default 20)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare p public.notification_preferences;t timestamp;minute integer;slot integer;job public.scheduled_checkins;
 result jsonb='[]';devices jsonb;fact public.memories;checkin_reason text;
begin
 update public.scheduled_checkins set status='unknown',outcome_detail='Worker lease expired; delivery unconfirmed.' where status='sending' and lease_until<p_now;
 update public.scheduled_checkins set status='suppressed',outcome_detail='Expired before dispatch.' where status='queued' and due_at<p_now-interval '1 day';
 for p in select * from public.notification_preferences where timezone is not null
  and (checkins_enabled or suggestions_enabled or birthdays_enabled) order by owner_id for update skip locked loop
  t=p_now at time zone p.timezone;minute=extract(hour from t)::integer*60+extract(minute from t)::integer;
  if public.morrow_is_quiet(minute,p.quiet_start,p.quiet_end) or not extract(dow from t)::integer=any(p.weekdays)
   or public.morrow_routine_blocks(p.owner_id,p.companion_id,p_now,p.timezone) then continue; end if;
  if not exists(select 1 from public.device_tokens where owner_id=p.owner_id and updated_at>p_now-interval '90 days') then continue; end if;
  if (select count(*) from public.scheduled_checkins where owner_id=p.owner_id and local_date=t::date and status<>'queued')>=p.max_per_day then continue; end if;
  foreach slot in array array_prepend(p.local_minute,p.additional_minutes) loop
   if (p.checkins_enabled or p.suggestions_enabled) and public.morrow_inactivity_allowed(p.owner_id,p.companion_id,p_now,p.inactivity_days) and minute>=slot and minute<slot+60
    and not exists(select 1 from public.scheduled_checkins where owner_id=p.owner_id and kind='checkin' and local_date=t::date and slot_minute=slot) then
    fact=null;
    select m.* into fact from public.memories m join public.companions c on c.id=m.companion_id and c.owner_id=m.owner_id
     where m.owner_id=p.owner_id and m.companion_id=p.companion_id and c.memory_enabled
      and m.verification not in ('unverified','superseded') and (m.expires_at is null or m.expires_at>p_now)
      and ((m.kind='event' and m.temporal_status not in ('completed','cancelled')
        and public.morrow_event_date(m.attributes,p_now,coalesce(m.attributes->>'timezone',p.timezone)) between t::date-3 and t::date+1)
       or (m.kind='routine' and coalesce(m.attributes->'weekdays','[]') @> to_jsonb(array[extract(dow from t)::integer]) and not coalesce((m.attributes->>'skip')::boolean,false))
       or (m.kind='development' and m.updated_at>p_now-interval '14 days'))
     order by case when m.kind='event' then 0 when m.kind='routine' then 1 else 2 end,m.updated_at desc limit 1;
    if not p.checkins_enabled and fact.id is null then continue; end if;
    checkin_reason=case when fact.id is null and p.inactivity_days>0 then 'User enabled a check-in after '||p.inactivity_days||' days without conversation. They do not owe a reply.' when fact.id is null then 'User requested a recurring check-in at this local time.'
     else 'User enabled contextual check-ins. Relevant user-stated detail: '||left(fact.content,1000)||
      case when fact.kind='event' then ' Event date: '||coalesce(public.morrow_event_date(fact.attributes,p_now,coalesce(fact.attributes->>'timezone',p.timezone))::text,'unresolved')||'. Planned events are not proof they happened.' else '' end end;
    insert into public.scheduled_checkins(owner_id,kind,due_at,local_date,slot_minute,preference_revision,reason,source_memory_id,source_updated_at,requires_memory)
     values(p.owner_id,'checkin',p_now,t::date,slot,p.revision,checkin_reason,fact.id,fact.updated_at,fact.id is not null) on conflict do nothing;
   end if;
  end loop;
  select * into job from public.scheduled_checkins where owner_id=p.owner_id and status='queued' and due_at<=p_now and preference_revision=p.revision
   and ((kind='checkin' and (p.checkins_enabled or p.suggestions_enabled)) or (kind='followup' and p.checkins_enabled) or (kind='important_date' and p.birthdays_enabled))
   order by case when kind='checkin' then 1 else 0 end,due_at,id limit 1 for update;
  if not found then continue; end if;
  update public.scheduled_checkins set status='sending',local_date=t::date,lease=gen_random_uuid(),lease_until=p_now+interval '2 minutes',
   reason=coalesce(reason,'User explicitly scheduled this reminder.') where id=job.id returning * into job;
  select jsonb_agg(jsonb_build_object('installation_id',installation_id,'token',token)) into devices from public.device_tokens where owner_id=p.owner_id and updated_at>p_now-interval '90 days';
  result=result||jsonb_build_array(jsonb_build_object('id',job.id,'lease',job.lease,'owner_id',job.owner_id,'companion_id',p.companion_id,'reason',job.reason,'devices',devices));
  exit when jsonb_array_length(result)>=least(greatest(p_limit,1),100);
 end loop;
 return jsonb_build_object('jobs',result);
end; $$;
-- END 202611030015_inactivity_checkins.sql

-- BEGIN 202611030016_natural_friend.sql
alter table public.profiles add column timezone_automatic boolean not null default false,
 add column reply_mode text not null default 'text' check(reply_mode in ('text','voice'));

create function public.morrow_save_friend_introduction(p_owner text,p_age_group text,p_language text,p_timezone text,p_automatic boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 perform public.morrow_save_introduction(p_owner,p_age_group,p_language,p_timezone);
 if p_automatic is null then raise exception 'invalid_input'; end if;
 update public.profiles set timezone_automatic=p_automatic where user_id=p_owner returning to_jsonb(profiles.*) into result;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_save_timezone(p_owner text,p_timezone text,p_automatic boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if p_automatic is null or p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'invalid_input'; end if;
 update public.profiles set timezone=p_timezone,timezone_automatic=p_automatic,updated_at=now()
 where user_id=p_owner returning to_jsonb(profiles.*) into result;
 if result is null then raise exception 'not_found'; end if;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_reply_mode(p_owner text,p_mode text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if p_mode is null or p_mode not in ('text','voice') then raise exception 'invalid_input'; end if;
 update public.profiles set reply_mode=p_mode,updated_at=now() where user_id=p_owner returning to_jsonb(profiles.*) into result;
 if result is null then raise exception 'not_found'; end if;
 return jsonb_build_object('profile',result);
end; $$;

-- Called only after the client explicitly accepts personal companion mode.
-- Existing opt-outs are never silently converted into consent by migration.
create function public.morrow_activate_friend_mode(p_owner text,p_companion uuid,p_consent boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.companions;result jsonb;
begin
 if p_consent is distinct from true then raise exception 'consent_required'; end if;
 perform public.morrow_require_eligible(p_owner);
 select * into c from public.companions where owner_id=p_owner and id=p_companion for update;
 if not found then raise exception 'not_found'; end if;
 perform public.morrow_save_companion(p_owner,c.name,c.communication_style,c.interests,c.response_length,true,c.retention_days);
 result=public.morrow_set_learning(p_owner,p_companion,true);
 return result;
end; $$;

create function public.morrow_require_friend_mode(p_owner text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 perform public.morrow_require_eligible(p_owner);
 if not exists(select 1 from public.companions where owner_id=p_owner and memory_enabled and learning_enabled)
 then raise exception 'personal_companion_required'; end if;
 return jsonb_build_object('ok',true);
end; $$;

do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
  'morrow_save_friend_introduction','morrow_save_timezone','morrow_reply_mode','morrow_activate_friend_mode','morrow_require_friend_mode') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
-- END 202611030016_natural_friend.sql

-- BEGIN 202611030017_reply_reports.sql
-- Additive moderation queue. Existing conversations and settings are untouched.
create table public.content_reports (
 id uuid primary key default gen_random_uuid(),
 owner_id text not null references public.profiles(user_id) on delete cascade,
 request_id uuid not null,
 message_id uuid references public.messages(id) on delete set null,
 message_snapshot text not null check(length(message_snapshot) between 1 and 12000),
 reason text not null check(reason in ('unsafe','inaccurate','other')),
 details text not null default '' check(length(details)<=2000),
 status text not null default 'new' check(status in ('new','reviewed','action_taken','dismissed')),
 created_at timestamptz not null default now(), reviewed_at timestamptz,
 unique(owner_id,request_id)
);
create index content_reports_review on public.content_reports(status,created_at);
alter table public.content_reports enable row level security;
revoke all on public.content_reports from anon,authenticated;
grant all on public.content_reports to service_role;
-- Only the verified API returns a receipt. Snapshots and moderation queues are
-- not directly exposed to browser/mobile database clients.
create function public.morrow_report_message(p_owner text,p_request uuid,p_message uuid,p_reason text,p_details text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.content_reports; snapshot text;
begin
 if p_request is null or p_reason is null or p_reason not in ('unsafe','inaccurate','other')
  or p_details is null or length(p_details)>2000 then raise exception 'invalid_input'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 select * into r from public.content_reports where owner_id=p_owner and request_id=p_request;
 if found then
  if r.message_id is distinct from p_message or r.reason<>p_reason or r.details<>p_details then raise exception 'request_conflict'; end if;
  return jsonb_build_object('report',jsonb_build_object('id',r.id,'status',r.status));
 end if;
 select m.content into snapshot from public.messages m join public.conversations c on c.id=m.conversation_id and c.owner_id=m.owner_id
  where m.id=p_message and m.owner_id=p_owner and m.role='assistant' and m.status='completed';
 if snapshot is null or snapshot='' then raise exception 'not_found'; end if;
 if (select count(*) from public.content_reports where owner_id=p_owner and created_at>now()-interval '1 day')>=20 then raise exception 'rate_limited'; end if;
 insert into public.content_reports(owner_id,request_id,message_id,message_snapshot,reason,details)
  values(p_owner,p_request,p_message,snapshot,p_reason,p_details) returning * into r;
 return jsonb_build_object('report',jsonb_build_object('id',r.id,'status',r.status));
end; $$;

create function public.morrow_review_report(p_report uuid,p_status text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_status is null or p_status not in ('reviewed','action_taken','dismissed') then raise exception 'invalid_input'; end if;
 update public.content_reports set status=p_status,reviewed_at=now() where id=p_report;
 if not found then raise exception 'not_found'; end if;
 return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_report_export(p_owner text,p_after text default '')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare rows jsonb;begin
 if exists(select 1 from public.account_deletions where owner_id=p_owner) then raise exception 'account_deleted'; end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') into rows from
  (select id,message_id,message_snapshot,reason,details,status,created_at,reviewed_at from public.content_reports
   where owner_id=p_owner and id::text>p_after order by id limit 201)r;
 return jsonb_build_object('section','reports','rows',coalesce((select jsonb_agg(value) from jsonb_array_elements(rows) with ordinality e(value,n) where n<=200),'[]'),
  'next_cursor',case when jsonb_array_length(rows)>200 then rows->199->>'id' else null end);
end; $$;

create function public.morrow_report_cleanup() returns jsonb language plpgsql security invoker set search_path='' as $$
begin delete from public.content_reports where created_at<now()-interval '90 days'; return jsonb_build_object('ok',true);end; $$;
do $$ declare fn regprocedure;begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in
  ('morrow_report_message','morrow_review_report','morrow_report_export','morrow_report_cleanup') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
-- END 202611030017_reply_reports.sql

-- BEGIN 202611030018_billing.sql
-- Billing is OFF. Adding infrastructure never starts a trial, sells a product,
-- charges a customer or changes existing free-testing access.
create table public.billing_configuration (
 singleton boolean primary key default true check(singleton),
 sales_enabled boolean not null default false,
 enforcement_enabled boolean not null default false,
 monthly_product_id text, monthly_base_plan_id text,
 intro_days integer check(intro_days between 0 and 90),
 free_daily_messages integer check(free_daily_messages between 1 and 10000),
 premium_daily_messages integer check(premium_daily_messages between 1 and 10000),
 free_daily_voice integer check(free_daily_voice between 0 and 20),
 premium_daily_voice integer check(premium_daily_voice between 0 and 20),
 check(not sales_enabled or (monthly_product_id is not null and monthly_base_plan_id is not null
  and length(monthly_product_id)>0 and length(monthly_base_plan_id)>0)),
 check(not enforcement_enabled or (sales_enabled and intro_days is not null and free_daily_messages is not null
  and premium_daily_messages is not null and free_daily_voice is not null and premium_daily_voice is not null))
);
insert into public.billing_configuration(singleton) values(true);
create table public.billing_accounts (
 owner_id text primary key references public.profiles(user_id) on delete cascade,
 account_ref uuid not null unique default gen_random_uuid(), intro_started_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.subscriptions (
 id uuid primary key default gen_random_uuid(),
 owner_id text not null references public.profiles(user_id) on delete cascade,
 token_hash text not null unique check(token_hash~'^[0-9a-f]{64}$'),
 encrypted_token text not null check(length(encrypted_token) between 1 and 16000),
 product_id text not null, base_plan_id text not null,
 state text not null check(state in ('pending','active','grace','canceled','expired','paused','hold','revoked')),
 expires_at timestamptz, acknowledged boolean not null default false, auto_renew boolean not null default false,
 verified_at timestamptz not null, created_at timestamptz not null default now()
);
create index subscriptions_owner on public.subscriptions(owner_id,expires_at desc);
create table public.billing_usage (
 owner_id text not null references public.profiles(user_id) on delete cascade,
 operation_id uuid not null, kind text not null check(kind in ('chat','greeting','voice','verification')),
 created_at timestamptz not null default now(), primary key(owner_id,operation_id,kind)
);
create index billing_usage_window on public.billing_usage(owner_id,created_at desc);
do $$ declare t text;begin
 foreach t in array array['billing_configuration','billing_accounts','subscriptions','billing_usage'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end; $$;

create function public.morrow_billing_status(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare c public.billing_configuration; a public.billing_accounts; s public.subscriptions;
 mode text='free_testing'; trial_end timestamptz; chat_used integer; voice_used integer;
begin
 if not exists(select 1 from public.profiles where user_id=p_owner) then raise exception 'not_found'; end if;
 select * into c from public.billing_configuration where singleton;
 if not c.sales_enabled and not c.enforcement_enabled then
  return jsonb_build_object('mode',mode,'available',false,'enforced',false,'premium',false);
 end if;
 insert into public.billing_accounts(owner_id) values(p_owner) on conflict do nothing;
 if c.enforcement_enabled then update public.billing_accounts set intro_started_at=coalesce(intro_started_at,now()) where owner_id=p_owner; end if;
 select * into a from public.billing_accounts where owner_id=p_owner;
 select * into s from public.subscriptions where owner_id=p_owner and acknowledged
  and state in ('active','grace','canceled') and expires_at>now() and verified_at>now()-interval '24 hours'
  order by expires_at desc limit 1;
 trial_end=a.intro_started_at+make_interval(days=>c.intro_days);
 if s.id is not null then mode='premium';
 elsif c.enforcement_enabled then mode=case when trial_end>now() then 'introductory' else 'expired' end; end if;
 select count(*) filter(where kind in ('chat','greeting')),count(*) filter(where kind='voice') into chat_used,voice_used
  from public.billing_usage where owner_id=p_owner and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 return jsonb_build_object('mode',mode,'available',c.sales_enabled,'enforced',c.enforcement_enabled,'premium',s.id is not null,
  'account_ref',a.account_ref,'product_id',c.monthly_product_id,'base_plan_id',c.monthly_base_plan_id,
  'trial_ends_at',trial_end,'expires_at',s.expires_at,'auto_renew',s.auto_renew,
  'messages_used_today',chat_used,'voice_requests_used_today',voice_used,
  'messages_limit',case when s.id is not null then c.premium_daily_messages else c.free_daily_messages end,
  'voice_limit',case when s.id is not null then c.premium_daily_voice else c.free_daily_voice end);
end; $$;

create function public.morrow_billing_attempt(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 if (select count(*) from public.billing_usage where owner_id=p_owner and kind='verification' and created_at>now()-interval '1 minute')>=10 then raise exception 'rate_limited'; end if;
 insert into public.billing_usage(owner_id,operation_id,kind) values(p_owner,gen_random_uuid(),'verification');
 return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_apply_subscription(p_owner text,p_account_ref uuid,p_token_hash text,p_linked_hash text,
 p_encrypted_token text,p_product text,p_base_plan text,p_state text,p_expires timestamptz,p_acknowledged boolean,p_auto_renew boolean,p_verified_at timestamptz)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare existing public.subscriptions; c public.billing_configuration;
begin
 select * into c from public.billing_configuration where singleton;
 if not c.sales_enabled then raise exception 'billing_unavailable'; end if;
 if p_product is distinct from c.monthly_product_id or p_base_plan is distinct from c.monthly_base_plan_id
  or not exists(select 1 from public.billing_accounts where owner_id=p_owner and account_ref=p_account_ref)
  or p_verified_at is null or p_verified_at>now()+interval '1 minute' or p_verified_at<now()-interval '5 minutes'
  then raise exception 'invalid_purchase'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_token_hash,1));
 select * into existing from public.subscriptions where token_hash=p_token_hash;
 if existing.id is not null and existing.owner_id<>p_owner then raise exception 'purchase_conflict'; end if;
 if p_linked_hash is not null and exists(select 1 from public.subscriptions where token_hash=p_linked_hash and owner_id<>p_owner)
  then raise exception 'purchase_conflict'; end if;
 -- An older HTTP/provider response cannot undo a later verified lifecycle update.
 if existing.verified_at is not null and existing.verified_at>p_verified_at then return public.morrow_billing_status(p_owner); end if;
 if existing.state='revoked' and p_state<>'revoked' then return public.morrow_billing_status(p_owner); end if;
 insert into public.subscriptions(owner_id,token_hash,encrypted_token,product_id,base_plan_id,state,expires_at,acknowledged,auto_renew,verified_at)
 values(p_owner,p_token_hash,p_encrypted_token,p_product,p_base_plan,p_state,p_expires,p_acknowledged,p_auto_renew,p_verified_at)
 on conflict(token_hash) do update set encrypted_token=excluded.encrypted_token,product_id=excluded.product_id,
  base_plan_id=excluded.base_plan_id,state=excluded.state,expires_at=excluded.expires_at,acknowledged=excluded.acknowledged,
  auto_renew=excluded.auto_renew,verified_at=excluded.verified_at;
 if p_linked_hash is not null and p_linked_hash<>p_token_hash then
  update public.subscriptions set state='revoked',expires_at=least(expires_at,now()),verified_at=p_verified_at
   where token_hash=p_linked_hash and owner_id=p_owner and verified_at<=p_verified_at;
 end if;
 return public.morrow_billing_status(p_owner);
end; $$;

create function public.morrow_subscription_tokens(p_owner text) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('subscriptions',coalesce(jsonb_agg(to_jsonb(s)),'[]')) from
 (select token_hash,encrypted_token from public.subscriptions where owner_id=p_owner and state<>'revoked' order by verified_at desc limit 3)s;
$$;
create function public.morrow_subscription_owner(p_hash text) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('owner',owner_id) from public.subscriptions where token_hash=p_hash;
$$;

create function public.morrow_invalidate_subscription(p_owner text,p_hash text,p_verified_at timestamptz) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 if p_verified_at is null or p_verified_at>now()+interval '1 minute' or p_verified_at<now()-interval '5 minutes' then raise exception 'invalid_input'; end if;
 update public.subscriptions set state='revoked',expires_at=least(coalesce(expires_at,now()),now()),auto_renew=false,verified_at=p_verified_at
  where owner_id=p_owner and token_hash=p_hash and verified_at<=p_verified_at;
 return public.morrow_billing_status(p_owner);
end; $$;

create function public.morrow_reserve_usage(p_owner text,p_operation uuid,p_kind text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare s jsonb; used integer; cap integer;
begin
 if not (select enforcement_enabled from public.billing_configuration where singleton) then return jsonb_build_object('ok',true); end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 s=public.morrow_billing_status(p_owner);
 if s->>'mode'='expired' then raise exception 'subscription_required'; end if;
 if exists(select 1 from public.billing_usage where owner_id=p_owner and operation_id=p_operation and kind=p_kind) then return jsonb_build_object('ok',true); end if;
 if p_kind in ('chat','greeting') then cap=(s->>'messages_limit')::integer;used=(s->>'messages_used_today')::integer;
 elsif p_kind='voice' then cap=(s->>'voice_limit')::integer;used=(s->>'voice_requests_used_today')::integer;
 else raise exception 'invalid_input';end if;
 if cap is null or used>=cap then raise exception 'usage_limit'; end if;
 insert into public.billing_usage(owner_id,operation_id,kind) values(p_owner,p_operation,p_kind);
 return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_access_begin_turn(p_owner text,p_conversation uuid,p_request uuid,p_content text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;begin
 result=public.morrow_begin_turn(p_owner,p_conversation,p_request,p_content);
 if result->>'status'='running' then perform public.morrow_reserve_usage(p_owner,coalesce((result->>'request_id')::uuid,p_request),'chat');end if;
 return result;
end; $$;
create function public.morrow_access_begin_greeting(p_owner text,p_conversation uuid,p_request uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;begin
 result=public.morrow_begin_greeting(p_owner,p_conversation,p_request);
 if result->>'status'='running' then perform public.morrow_reserve_usage(p_owner,coalesce((result->>'request_id')::uuid,p_request),'greeting');end if;
 return result;
end; $$;
create function public.morrow_access_voice(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;begin
 result=public.morrow_authorize_voice(p_owner);perform public.morrow_reserve_usage(p_owner,gen_random_uuid(),'voice');return result;
end; $$;

create function public.morrow_billing_export(p_owner text,p_section text,p_after text default '') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare rows jsonb;begin
 if exists(select 1 from public.account_deletions where owner_id=p_owner) then raise exception 'account_deleted';end if;
 if p_section='subscriptions' then
  select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') into rows from (select id,product_id,base_plan_id,state,expires_at,acknowledged,auto_renew,verified_at,created_at
   from public.subscriptions where owner_id=p_owner and id::text>p_after order by id limit 201)s;
 elsif p_section='usage' then
  select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') into rows from (select operation_id::text||kind as id,kind,created_at
   from public.billing_usage where owner_id=p_owner and operation_id::text||kind>p_after order by operation_id::text||kind limit 201)s;
 else raise exception 'invalid_input';end if;
 return jsonb_build_object('section',p_section,'rows',coalesce((select jsonb_agg(value) from jsonb_array_elements(rows) with ordinality e(value,n) where n<=200),'[]'),
  'next_cursor',case when jsonb_array_length(rows)>200 then rows->199->>'id' else null end);
end; $$;
create function public.morrow_billing_cleanup() returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 delete from public.billing_usage where created_at<now()-interval '90 days';
 delete from public.subscriptions where expires_at<now()-interval '90 days' and state in ('expired','revoked');
 return jsonb_build_object('ok',true);
end; $$;
do $$ declare fn regprocedure;begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in
 ('morrow_billing_status','morrow_billing_attempt','morrow_apply_subscription','morrow_subscription_tokens','morrow_subscription_owner','morrow_invalidate_subscription',
 'morrow_reserve_usage','morrow_access_begin_turn','morrow_access_begin_greeting','morrow_access_voice','morrow_billing_export','morrow_billing_cleanup') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
-- END 202611030018_billing.sql

-- BEGIN 202611040019_review_guests.sql
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
-- END 202611040019_review_guests.sql

-- BEGIN 202611040020_friend_preferences.sql
-- Extend the existing owned companion; preserve accounts, names, consent and history.
alter table public.companions
 add column personality_keys text[] not null default '{}' check(cardinality(personality_keys)<=2 and array_position(personality_keys,null) is null
  and personality_keys <@ array['warm_caring','funny_playful','calm_understanding','positive_motivating','curious_intellectual','friendly_outgoing','wise_thoughtful','casual_relaxed']::text[]),
 add column support_preferences text[] not null default '{}' check(cardinality(support_preferences)<=4 and array_position(support_preferences,null) is null
  and support_preferences <@ array['emotional_support','daily_companionship','motivation','personal_growth','learning','friendship','productivity','perspectives','creativity','relaxation','language_practice','confidence']::text[]),
 add column interaction_style text check(interaction_style in ('casual_natural','warm_affectionate','calm_gentle','funny_playful','direct','thoughtful_detailed')),
 add column learning_interests text not null default '' check(length(learning_interests)<=400),
 add column personal_goals text not null default '' check(length(personal_goals)<=600),
 add column additional_information text not null default '' check(length(additional_information)<=600),
 add column preferences_completed_at timestamptz;

-- Legacy settings remain effective until the owner explicitly chooses new preferences.
create function public.morrow_save_friend_preferences(p_owner text,p_companion uuid,p_name text,
 p_personalities text[],p_support text[],p_communication text,p_learning text,p_goals text,p_additional text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 perform public.morrow_require_eligible(p_owner);
 if p_name is null or length(btrim(p_name)) not between 1 and 24 or p_name ~ '[[:cntrl:]]'
  or p_personalities is null or cardinality(p_personalities) not between 1 and 2
  or cardinality(p_personalities)<>(select count(distinct value) from unnest(p_personalities) value)
  or p_support is null or cardinality(p_support)>4
  or cardinality(p_support)<>(select count(distinct value) from unnest(p_support) value)
  or p_communication is null or p_learning is null or p_goals is null or p_additional is null
 then raise exception 'invalid_input'; end if;
 update public.companions set name=btrim(p_name),personality_keys=p_personalities,
  support_preferences=p_support,interaction_style=p_communication,learning_interests=btrim(p_learning),
  personal_goals=btrim(p_goals),additional_information=btrim(p_additional),
  preferences_completed_at=coalesce(preferences_completed_at,now()),updated_at=now()
  where id=p_companion and owner_id=p_owner returning to_jsonb(companions.*) into result;
 if result is null then raise exception 'not_found'; end if;
 return jsonb_build_object('companion',result);
end; $$;
revoke all on function public.morrow_save_friend_preferences(text,uuid,text,text[],text[],text,text,text,text) from public,anon,authenticated;
grant execute on function public.morrow_save_friend_preferences(text,uuid,text,text[],text[],text,text,text,text) to service_role;
-- END 202611040020_friend_preferences.sql

-- Make the new schema visible through the Data API after commit.
notify pgrst,'reload schema';
commit;

select jsonb_build_object('status','installed','application','Ai Companion',
 'firebase_project',(select firebase_project_id from public.identity_configuration where singleton),
 'application_tables',(select count(*) from pg_tables where schemaname='public' and tablename in ('profiles','companions','conversations','turn_requests','messages','memories','memory_tombstones','memory_jobs','interaction_patterns','notification_preferences','device_tokens','scheduled_checkins','voice_usage','identity_configuration','account_deletions','consent_events','content_reports','billing_configuration','billing_accounts','subscriptions','billing_usage','review_configuration','review_guest_sessions')),
 'next_step','Configure server secrets and deploy the Edge Functions. Then sign up in the app.') as setup_result;
