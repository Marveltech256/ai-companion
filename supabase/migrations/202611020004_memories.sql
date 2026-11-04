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
