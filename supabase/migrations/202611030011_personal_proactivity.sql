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
