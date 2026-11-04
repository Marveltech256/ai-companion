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
