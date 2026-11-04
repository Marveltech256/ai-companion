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
