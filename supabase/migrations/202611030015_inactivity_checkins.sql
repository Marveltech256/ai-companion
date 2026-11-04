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

