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
