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
