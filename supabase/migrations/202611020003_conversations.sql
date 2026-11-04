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
