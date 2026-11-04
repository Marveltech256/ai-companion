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
