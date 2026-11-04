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
