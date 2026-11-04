-- Additive local candidate. Inspect the target schema/history before deployment.
alter table public.profiles add column preferred_name text check(length(preferred_name)<=80),
 add column timezone text, add column language text check(length(language)<=40),
 add column general_location text check(length(general_location)<=120);
alter table public.companions add column introduced_at timestamptz,
 add column name_question_asked_at timestamptz;
alter table public.turn_requests add column kind text not null default 'user'
 check(kind in ('user','greeting','proactive')), add column context_timezone text,
 add column greeting_asks_name boolean not null default false;
create unique index one_conversation_greeting on public.turn_requests(conversation_id) where kind='greeting';

create function public.morrow_memory_kind(p_category text) returns text
language sql immutable set search_path='' as $$
 select case p_category when 'personal_information' then 'identity' when 'identity' then 'identity'
 when 'routines' then 'routine' when 'preferences' then 'preference' when 'communication_preferences' then 'preference'
 when 'people' then 'relationship' when 'relationships' then 'relationship'
 when 'important_dates' then 'event' when 'events' then 'event'
 when 'goals' then 'development' when 'personal_development' then 'development'
 else 'conversation' end;
$$;
alter table public.memories drop constraint memories_category_check;
alter table public.memories add constraint memories_category_check check(category in (
 'personal_information','preferences','people','experiences','important_dates','goals','discussions','communication_preferences',
 'identity','routines','relationships','events','conversation_history','personal_development'));
alter table public.memories add column kind text generated always as (public.morrow_memory_kind(category)) stored,
 add column attributes jsonb not null default '{}'::jsonb check(jsonb_typeof(attributes)='object'),
 add column verification text not null default 'user_stated' check(verification in ('user_stated','user_confirmed','unverified','superseded')),
 add column temporal_status text not null default 'durable' check(temporal_status in ('durable','temporary','planned','completed','cancelled','unresolved'));
create index continuity_memory_lookup on public.memories(owner_id,companion_id,kind,updated_at desc);

create function public.morrow_save_personal_profile(p_owner text,p_preferred_name text,p_display_name text,
 p_timezone text,p_language text,p_location text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb; begin
 if p_timezone is not null and not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'invalid_input'; end if;
 update public.profiles set preferred_name=nullif(btrim(p_preferred_name),''),display_name=nullif(btrim(p_display_name),''),
 timezone=p_timezone,language=nullif(btrim(p_language),''),general_location=nullif(btrim(p_location),''),updated_at=now()
 where user_id=p_owner returning to_jsonb(profiles.*) into result;
 if not found then raise exception 'not_found'; end if;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_snapshot_context() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 select coalesce(p.timezone,n.timezone) into new.context_timezone from public.profiles p
 left join public.notification_preferences n on n.owner_id=p.user_id where p.user_id=new.owner_id;
 if new.context_timezone is null then
  select m.attributes->>'value' into new.context_timezone from public.memories m join public.companions c on c.id=m.companion_id and c.owner_id=m.owner_id
  where m.owner_id=new.owner_id and c.memory_enabled and m.kind='identity' and m.attributes->>'field'='timezone'
   and m.verification not in ('unverified','superseded') and (m.expires_at is null or m.expires_at>now()) order by m.user_edited desc,m.updated_at desc limit 1;
 end if;
 if new.context_timezone is not null and not exists(select 1 from pg_timezone_names where name=new.context_timezone) then new.context_timezone=null; end if;
 return new;
end; $$;
create trigger snapshot_turn_context before insert on public.turn_requests for each row execute function public.morrow_snapshot_context();

create function public.morrow_normalize_attributes(p_attributes jsonb,p_quote text,p_source_time timestamptz,p_zone text,p_manual boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare a jsonb=coalesce(p_attributes,'{}'); result jsonb='{}'; item jsonb; key text; z text=p_zone; d date; relative integer;
begin
 if jsonb_typeof(a)<>'object' or pg_column_size(a)>4000 then raise exception 'invalid_input'; end if;
 for key,item in select * from jsonb_each(a) loop
   if key not in ('field','value','weekdays','start_minute','end_minute','on_date','relative_days','timezone','routine_kind','skip','block_notifications','stability','event_status','annual','month','day')
     then raise exception 'invalid_input'; end if;
 end loop;
 if a->>'field' is not null then
   if a->>'field' not in ('preferred_name','full_name','location','language','timezone','wake','sleep','work','study','exercise','activity','other') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('field',a->>'field');
 end if;
 if a->>'value' is not null then
   if length(a->>'value') not between 1 and 160 or (not p_manual and position(lower(a->>'value') in lower(p_quote))=0) then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('value',a->>'value');
 end if;
 foreach key in array array['start_minute','end_minute'] loop
   if a->>key is not null then
     if a->>key !~ '^\d{1,4}$' or (a->>key)::integer not between 0 and 1439 then raise exception 'invalid_input'; end if;
     result=result||jsonb_build_object(key,(a->>key)::integer);
   end if;
 end loop;
 if a->'weekdays' is not null and a->'weekdays'<>'null' then
   if jsonb_typeof(a->'weekdays')<>'array' or jsonb_array_length(a->'weekdays')>7 then raise exception 'invalid_input'; end if;
   for item in select value from jsonb_array_elements(a->'weekdays') loop
     if item::text !~ '^[0-6]$' then raise exception 'invalid_input'; end if;
   end loop;
   result=result||jsonb_build_object('weekdays',a->'weekdays');
 end if;
 foreach key in array array['skip','block_notifications','annual'] loop
   if a->>key is not null then
     if jsonb_typeof(a->key)<>'boolean' then raise exception 'invalid_input'; end if;
     result=result||jsonb_build_object(key,a->key);
   end if;
 end loop;
 if a->>'annual'='true' then
  if a->>'month' !~ '^\d{1,2}$' or a->>'day' !~ '^\d{1,2}$' or a->>'month' is null or a->>'day' is null then raise exception 'invalid_input'; end if;
  perform make_date(2000,(a->>'month')::integer,(a->>'day')::integer);
  if not p_manual and p_quote !~* '(birthday|anniversary|annually|every year|each year)' then raise exception 'invalid_input'; end if;
  result=result||jsonb_build_object('month',(a->>'month')::integer,'day',(a->>'day')::integer);
 end if;
 if a->>'routine_kind' is not null then
   if a->>'routine_kind' not in ('wake','sleep','work','study','exercise','activity','other') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('routine_kind',a->>'routine_kind');
 end if;
 if a->>'stability' is not null then
   if a->>'stability' not in ('durable','temporary','event','uncertain') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('stability',a->>'stability');
 end if;
 if a->>'event_status' is not null then
   if a->>'event_status' not in ('planned','completed','cancelled','uncertain') then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('event_status',a->>'event_status');
 end if;
 if a->>'timezone' is not null and (p_manual or position(a->>'timezone' in p_quote)>0) then z=a->>'timezone'; end if;
 if z is not null and not exists(select 1 from pg_timezone_names where name=z) then raise exception 'invalid_input'; end if;
 if z is not null then result=result||jsonb_build_object('timezone',z); end if;
 if a->>'relative_days' is not null then
   if a->>'relative_days' !~ '^-?\d{1,3}$' then raise exception 'invalid_input'; end if;
   relative=(a->>'relative_days')::integer;
   if relative not between -1 and 366 then raise exception 'invalid_input'; end if;
   result=result||jsonb_build_object('relative_days',relative,'observed_at',p_source_time);
   if z is not null then d=(p_source_time at time zone z)::date+relative; end if;
 end if;
 if a->>'on_date' is not null then
   if a->>'on_date' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_input'; end if;
   if p_manual or position(a->>'on_date' in p_quote)>0 then d=(a->>'on_date')::date; end if;
 end if;
 if d is not null then result=result||jsonb_build_object('on_date',d); end if;
 return result;
end; $$;

-- Old clients can still edit plain memories. Clear structured data when they
-- change the words without supplying a corresponding structured correction.
create function public.morrow_clear_stale_attributes() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.content is distinct from old.content or new.category is distinct from old.category or new.source_message_id is distinct from old.source_message_id) then
   new.attributes='{}';new.verification=case when new.user_edited then 'user_confirmed' else 'user_stated' end;new.temporal_status='durable';
 end if;
 return new;
end; $$;
create trigger clear_stale_attributes before update of content,category,source_message_id on public.memories
 for each row execute function public.morrow_clear_stale_attributes();

create function public.morrow_save_structured_memory(p_owner text,p_companion uuid,p_id uuid,
 p_category text,p_title text,p_content text,p_expires_at timestamptz,p_attributes jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; a jsonb; z text; begin
 select coalesce(p.timezone,n.timezone) into z from public.profiles p left join public.notification_preferences n on n.owner_id=p.user_id where p.user_id=p_owner;
 a=public.morrow_normalize_attributes(p_attributes,p_content,now(),z,true);
 result=public.morrow_save_memory(p_owner,p_companion,p_id,p_category,p_title,p_content,p_expires_at);
 update public.memories set attributes=a,verification='user_confirmed',
 temporal_status=case when a->>'event_status'='cancelled' then 'cancelled' when a->>'annual'='true' then 'durable' when a->>'event_status'='completed' then 'completed'
 when a->>'stability'='uncertain' then 'unresolved' when a->>'stability'='temporary' then 'temporary'
 when kind='event' and a->>'on_date' is null then 'unresolved' when kind='event' then 'planned' else 'durable' end
 where id=(result->'memory'->>'id')::uuid and owner_id=p_owner returning to_jsonb(memories.*) into result;
 return jsonb_build_object('memory',result);
end; $$;

-- Preserve the original consent/lease/tombstone fences while allowing a short
-- explicitly grounded preferred name (for example Li) after the name question.
create or replace function public.morrow_apply_memory_job(p_owner text,p_request uuid,p_lease uuid,p_candidates jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.memory_jobs;c public.companions;m public.messages;candidate jsonb;
 fact_key text;quote text;category text;total integer=0;
begin
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
  if fact_key is null or fact_key !~ '^[a-z0-9_.:-]{1,120}$' or quote is null or length(quote)>2000
   or length(quote)<(case when candidate->'attributes'->>'field'='preferred_name' then 1 else 4 end)
   or position(quote in m.content)=0 or coalesce((candidate->>'confidence')::real,0)<.8 then continue; end if;
  if exists(select 1 from public.memory_tombstones where owner_id=p_owner and companion_id=c.id and memory_key=fact_key) then continue; end if;
  insert into public.memories(owner_id,companion_id,memory_key,category,title,content,source_quote,source_message_id,confidence,importance,expires_at)
   values(p_owner,c.id,fact_key,category,left(quote,80),quote,quote,m.id,(candidate->>'confidence')::real,(candidate->>'importance')::real,
    case when c.retention_days is null then null else now()+make_interval(days=>c.retention_days) end)
   on conflict(owner_id,companion_id,memory_key) do update set category=excluded.category,title=excluded.title,content=excluded.content,
    source_quote=excluded.source_quote,source_message_id=excluded.source_message_id,confidence=excluded.confidence,
    importance=excluded.importance,updated_at=now(),expires_at=excluded.expires_at where not memories.user_edited;
  if found then total=total+1; end if;
 end loop;
 update public.memory_jobs set status='completed',updated_at=now() where request_id=p_request;
 return jsonb_build_object('saved',total);
end; $$;

create function public.morrow_apply_companion_memory_job(p_owner text,p_request uuid,p_lease uuid,p_candidates jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; candidate jsonb; m public.messages; r public.turn_requests; a jsonb; stability text; expiry timestamptz;
begin
 result=public.morrow_apply_memory_job(p_owner,p_request,p_lease,p_candidates);
 if coalesce((result->>'saved')::integer,0)=0 then return result; end if;
 select * into m from public.messages where owner_id=p_owner and request_id=p_request and role='user';
 select * into r from public.turn_requests where owner_id=p_owner and id=p_request;
 for candidate in select value from jsonb_array_elements(p_candidates) loop
   a=public.morrow_normalize_attributes(candidate->'attributes',candidate->>'quote',m.created_at,r.context_timezone,false);
   stability=coalesce(a->>'stability','durable');
   expiry=case when stability='temporary' then m.created_at+interval '7 days'
     when public.morrow_memory_kind(candidate->>'category')='event' and a->>'annual' is distinct from 'true' then
       case when a->>'on_date' is not null and a->>'timezone' is not null
        then ((a->>'on_date')::date+30)::timestamp at time zone (a->>'timezone') else m.created_at+interval '30 days' end else null end;
   update public.memories set attributes=a,verification=case when stability='uncertain' then 'unverified' else 'user_stated' end,
    temporal_status=case when a->>'event_status'='cancelled' then 'cancelled' when a->>'annual'='true' then 'durable' when a->>'event_status'='completed' then 'completed'
     when stability='uncertain' then 'unresolved' when stability='temporary' then 'temporary'
     when kind='event' and a->>'on_date' is null then 'unresolved' when kind='event' then 'planned' else 'durable' end,
    expires_at=least(expires_at,expiry)
   where owner_id=p_owner and companion_id=(select companion_id from public.memory_jobs where request_id=p_request)
    and memory_key=candidate->>'key' and source_message_id=m.id and not user_edited;
 end loop;
 return result;
end; $$;

create or replace function public.morrow_claim_memory_job(p_owner text,p_request uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare j public.memory_jobs;c public.companions;m public.messages;r public.turn_requests;previous text;
begin
 select * into j from public.memory_jobs where owner_id=p_owner and request_id=p_request for update;
 if not found or j.status in ('completed','suppressed') or j.attempts>=5 or (j.status='running' and j.lease_until>now()) then return jsonb_build_object('job',null); end if;
 select * into c from public.companions where id=j.companion_id and owner_id=p_owner;
 select * into m from public.messages where owner_id=p_owner and request_id=p_request and role='user';
 select * into r from public.turn_requests where owner_id=p_owner and id=p_request;
 if m.id is null or not c.memory_enabled or c.consent_version<>j.consent_version or m.created_at<=c.memory_reset_at then
   update public.memory_jobs set status='suppressed',updated_at=now() where request_id=p_request;
   return jsonb_build_object('job',null);
 end if;
 select left(content,1200) into previous from public.messages where owner_id=p_owner and conversation_id=m.conversation_id
  and role='assistant' and status='completed' and seq<m.seq order by seq desc limit 1;
 update public.memory_jobs set status='running',attempts=attempts+1,lease=gen_random_uuid(),lease_until=now()+interval '60 seconds',updated_at=now()
  where request_id=p_request returning * into j;
 return jsonb_build_object('job',to_jsonb(j),'source',jsonb_build_object('id',m.id,'content',m.content,
  'created_at',m.created_at,'timezone',r.context_timezone,'previous_assistant',previous));
end; $$;

create function public.morrow_current_routines(p_owner text,p_companion uuid,p_now timestamptz,p_timezone text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare t timestamp; minute integer; day integer; result jsonb;
begin
 if p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone) then return '[]'; end if;
 t=p_now at time zone p_timezone;minute=extract(hour from t)::integer*60+extract(minute from t)::integer;day=extract(dow from t)::integer;
 with valid as (
  select m.* from public.memories m join public.companions c on c.id=m.companion_id and c.owner_id=m.owner_id
   where m.owner_id=p_owner and m.companion_id=p_companion and c.memory_enabled and m.kind='routine'
    and m.verification not in ('unverified','superseded') and (m.expires_at is null or m.expires_at>p_now)
 ), applicable as (
  select r.*,d.anchor from valid r cross join (values(t::date),(t::date-1)) d(anchor)
   where (r.attributes->>'on_date'=d.anchor::text or (r.attributes->>'on_date' is null
    and coalesce(r.attributes->'weekdays','[]') @> to_jsonb(array[extract(dow from d.anchor)::integer])
    and not exists(select 1 from valid e where e.attributes->>'on_date'=d.anchor::text
      and coalesce(e.attributes->>'routine_kind',e.attributes->>'field')=coalesce(r.attributes->>'routine_kind',r.attributes->>'field'))))
   and (d.anchor=t::date or ((r.attributes->>'start_minute')::integer>(r.attributes->>'end_minute')::integer
    and minute<(r.attributes->>'end_minute')::integer))
 ) select coalesce(jsonb_agg(to_jsonb(r)),'[]') into result from (
  select id,left(content,600) as content,attributes,verification,anchor as schedule_date,
   case when coalesce((attributes->>'skip')::boolean,false) then false
    when attributes->>'start_minute' is null or attributes->>'end_minute' is null then false
    when (attributes->>'start_minute')::integer=(attributes->>'end_minute')::integer then false
    else t>=anchor::timestamp+make_interval(mins=>(attributes->>'start_minute')::integer)
     and t<anchor::timestamp+make_interval(mins=>(attributes->>'end_minute')::integer)
      +case when (attributes->>'start_minute')::integer>(attributes->>'end_minute')::integer then interval '1 day' else interval '0' end
    end as active_now
  from applicable order by active_now desc,case when attributes->>'routine_kind' in ('work','sleep') then 0 else 1 end,user_edited desc,updated_at desc limit 12
 )r;
 return result;
end; $$;

create function public.morrow_event_date(p_attributes jsonb,p_now timestamptz,p_timezone text)
returns date language plpgsql stable set search_path='' as $$
declare today date;candidate date;year integer;offset_year integer;
begin
 if p_attributes->>'annual' is distinct from 'true' then return (p_attributes->>'on_date')::date; end if;
 if p_timezone is null then return null; end if;
 today=(p_now at time zone p_timezone)::date;year=extract(year from today)::integer;
 for offset_year in 0..8 loop
  begin candidate=make_date(year+offset_year,(p_attributes->>'month')::integer,(p_attributes->>'day')::integer);
   exception when datetime_field_overflow then continue; end;
  if candidate>=today then return candidate; end if;
 end loop;
 return null;
end; $$;

create function public.morrow_companion_context(p_owner text,p_companion uuid,p_query text default '',p_conversation uuid default null,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.companions;p public.profiles;z text;local_time timestamp;today date;facts jsonb='[]';
 identity jsonb;old_discussions jsonb='[]';q tsquery;preferred text;language text;location text;
begin
 select * into c from public.companions where id=p_companion and owner_id=p_owner;
 if not found then raise exception 'not_found'; end if;
 if p_conversation is not null and not exists(select 1 from public.conversations where id=p_conversation and owner_id=p_owner and companion_id=p_companion) then raise exception 'not_found'; end if;
 select * into p from public.profiles where user_id=p_owner;
 z=coalesce(p.timezone,(select timezone from public.notification_preferences where owner_id=p_owner));
 preferred=p.preferred_name;language=p.language;location=p.general_location;
 if c.memory_enabled then
   if preferred is null then select attributes->>'value' into preferred from public.memories where owner_id=p_owner and companion_id=p_companion
    and kind='identity' and attributes->>'field'='preferred_name' and verification not in ('unverified','superseded')
    and (expires_at is null or expires_at>p_now) order by user_edited desc,updated_at desc limit 1; end if;
   if z is null then select attributes->>'value' into z from public.memories where owner_id=p_owner and companion_id=p_companion
    and kind='identity' and attributes->>'field'='timezone' and verification not in ('unverified','superseded')
    and (expires_at is null or expires_at>p_now) order by user_edited desc,updated_at desc limit 1; end if;
 end if;
 if z is not null and not exists(select 1 from pg_timezone_names where name=z) then z=null; end if;
 preferred=coalesce(preferred,p.display_name);
 if z is not null then local_time=p_now at time zone z;today=local_time::date; end if;
 if c.memory_enabled then
   q=websearch_to_tsquery('simple',left(p_query,2000));
   select coalesce(jsonb_agg(to_jsonb(f)-'kind_rank'),'[]') into facts from (
    select * from (
    select id,memory_key,category,kind,left(content,1200) as content,attributes,verification,temporal_status,
     source_message_id,source_quote,confidence,importance,created_at,updated_at,expires_at,
     public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) as event_date,
     case when kind<>'event' then null when temporal_status in ('cancelled','completed') then temporal_status
      when public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) is null or coalesce(attributes->>'timezone',z) is null then 'unresolved'
      when public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z))<(p_now at time zone coalesce(attributes->>'timezone',z))::date then 'past_planned'
      when public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z))=(p_now at time zone coalesce(attributes->>'timezone',z))::date then 'today'
      else 'upcoming' end as event_state,
     row_number() over(partition by kind order by
      (kind='event' and temporal_status not in ('completed','cancelled') and public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) between today-7 and today+30) desc nulls last,
      (kind='preference' and (category='communication_preferences' or memory_key like '%communication%')) desc,
      (search_vector @@ q) desc,user_edited desc,updated_at desc) as kind_rank,
     (ts_rank_cd(search_vector,q)+importance*.3)::real as relevance
    from public.memories m where owner_id=p_owner and companion_id=p_companion and verification<>'superseded'
     and (expires_at is null or expires_at>p_now)
     and not(kind='identity' and attributes->>'field'='preferred_name' and preferred is not null and attributes->>'value' is distinct from preferred)
     and not(kind='identity' and preferred is not null and attributes->>'field' is null and memory_key ~ '(name|nickname)')
    ) ranked where kind_rank<=case when kind='event' then 6 when kind='routine' then 5 else 4 end
    order by case when kind_rank=1 and kind='identity' then 0 when kind_rank=1 and kind='routine' then 1
     when kind='event' and (public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) is null or public.morrow_event_date(attributes,p_now,coalesce(attributes->>'timezone',z)) between today-7 and today+30) then 2
     else 3 end, relevance desc,updated_at desc limit 32
   )f;
   select coalesce(jsonb_agg(to_jsonb(d)),'[]') into old_discussions from (
    select m.conversation_id,v.title,m.role,left(m.content,700) as content,m.created_at from public.messages m
     join public.conversations v on v.id=m.conversation_id and v.owner_id=m.owner_id
    where m.owner_id=p_owner and v.companion_id=p_companion and m.status='completed'
     and (p_conversation is null or m.conversation_id<>p_conversation)
     and (c.conversation_retention_days is null or v.updated_at>p_now-make_interval(days=>c.conversation_retention_days))
    order by m.created_at desc,m.seq desc limit 6
   )d;
 end if;
 identity=jsonb_build_object('preferred_name',preferred,'full_name',p.display_name,'language',language,'general_location',location,
  'source',case when p.preferred_name is not null or (preferred=p.display_name) then 'explicit_profile' else 'active_memory' end);
 return jsonb_build_object('identity',identity,'clock',jsonb_build_object('utc',p_now,'timezone',z,'local',local_time,'local_date',today),
  'first_meeting',jsonb_build_object('introduced',c.introduced_at is not null,'name_question_asked',c.name_question_asked_at is not null),
  'memories',facts,'current_routine',public.morrow_current_routines(p_owner,p_companion,p_now,z),'previous_discussions',old_discussions);
end; $$;

create function public.morrow_begin_greeting(p_owner text,p_conversation uuid,p_request uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v public.conversations;c public.companions;r public.turn_requests;h jsonb;ctx jsonb;t text;
begin
 select * into v from public.conversations where id=p_conversation and owner_id=p_owner for update;
 if not found then raise exception 'not_found'; end if;
 select * into c from public.companions where id=v.companion_id and owner_id=p_owner;
 select * into r from public.turn_requests where conversation_id=v.id and owner_id=p_owner and kind='greeting' for update;
 if found and r.status='completed' then
  select content into t from public.messages where owner_id=p_owner and request_id=r.id and role='assistant';
  return jsonb_build_object('status','completed','text',t,'request_id',r.id);
 end if;
 if r.id is not null and r.status='running' and r.lease_until>now() then raise exception 'turn_busy'; end if;
 if exists(select 1 from public.messages where owner_id=p_owner and conversation_id=v.id and role='user') then raise exception 'conversation_started'; end if;
 if v.active_request_id is not null and v.active_until>now() then raise exception 'turn_busy'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 if r.id is null and (select count(*) from public.turn_requests where owner_id=p_owner and created_at>now()-interval '1 minute')>=10 then raise exception 'rate_limited'; end if;
 ctx=public.morrow_companion_context(p_owner,c.id,'',v.id);
 if r.id is null then
  insert into public.turn_requests(id,owner_id,conversation_id,status,lease_until,consent_version,kind,greeting_asks_name)
   values(p_request,p_owner,v.id,'running',now()+interval '120 seconds',c.consent_version,'greeting',
    c.name_question_asked_at is null and ctx->'identity'->>'preferred_name' is null) returning * into r;
 else update public.turn_requests set status='running',lease=gen_random_uuid(),lease_until=now()+interval '120 seconds',updated_at=now() where id=r.id returning * into r; end if;
 insert into public.messages(owner_id,conversation_id,request_id,role,content,status) values(p_owner,v.id,r.id,'assistant','','pending')
  on conflict(request_id,role) do update set content='',status='pending';
 update public.conversations set active_request_id=r.id,active_until=r.lease_until where id=v.id;
 return jsonb_build_object('status','running','lease',r.lease,'request_id',r.id,'companion',to_jsonb(c),'history','[]'::jsonb,'consent_version',r.consent_version);
end; $$;

create or replace function public.morrow_enqueue_memory() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.kind<>'user' then return new; end if;
 insert into public.memory_jobs(request_id,owner_id,companion_id,consent_version)
  select new.id,new.owner_id,c.id,new.consent_version from public.conversations v join public.companions c on c.id=v.companion_id and c.owner_id=new.owner_id
  where v.id=new.conversation_id and c.memory_enabled and c.consent_version=new.consent_version on conflict do nothing;
 return new;
end; $$;
create function public.morrow_introduction_completed() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.status='completed' and old.status is distinct from 'completed' then
  update public.companions set introduced_at=coalesce(introduced_at,now()),
   name_question_asked_at=case when new.greeting_asks_name then coalesce(name_question_asked_at,now()) else name_question_asked_at end
   where owner_id=new.owner_id and id=(select companion_id from public.conversations where id=new.conversation_id and owner_id=new.owner_id);
 end if;
 return new;
end; $$;
create trigger record_introduction after update of status on public.turn_requests for each row execute function public.morrow_introduction_completed();
-- Greeting/proactive turns must not become inferred interaction observations.
drop trigger observe_completed_turn on public.turn_requests;
create trigger observe_completed_turn after update of status on public.turn_requests for each row when(new.kind='user') execute function public.morrow_observe_turn();

-- Structured metadata is included in the existing memory manager/export shape.
create or replace function public.morrow_messages(p_owner text,p_conversation uuid,p_before bigint default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.conversations where owner_id=p_owner and id=p_conversation) then raise exception 'not_found'; end if;
 select coalesce(jsonb_agg(to_jsonb(m) order by seq),'[]') into result from (
  select m.id,m.seq,m.request_id,m.role,m.content,m.created_at,r.kind,
   case when m.status='pending' and r.lease_until<now() then 'failed' else m.status end as status
   from public.messages m join public.turn_requests r on r.id=m.request_id and r.owner_id=m.owner_id
   where m.owner_id=p_owner and m.conversation_id=p_conversation and (p_before is null or m.seq<p_before)
   order by m.seq desc limit 50)m;
 return jsonb_build_object('messages',result);
end; $$;

create or replace function public.morrow_list_memories(p_owner text,p_companion uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;total integer;
begin
 if not exists(select 1 from public.companions where id=p_companion and owner_id=p_owner) then raise exception 'not_found'; end if;
 delete from public.memories where owner_id=p_owner and expires_at<=now();
 select count(*) into total from public.memories where owner_id=p_owner and companion_id=p_companion;
 select coalesce(jsonb_agg(to_jsonb(m)-'search_vector'),'[]') into result from (
  select * from public.memories where owner_id=p_owner and companion_id=p_companion order by updated_at desc limit 100)m;
 return jsonb_build_object('memories',result,'total',total,'pending_count',(select count(*) from public.memory_jobs where owner_id=p_owner and companion_id=p_companion and status in ('pending','running','failed') and attempts<5));
end; $$;
do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
 'morrow_memory_kind','morrow_save_personal_profile','morrow_snapshot_context','morrow_normalize_attributes',
 'morrow_clear_stale_attributes','morrow_save_structured_memory','morrow_apply_companion_memory_job',
 'morrow_companion_context','morrow_begin_greeting','morrow_introduction_completed','morrow_current_routines','morrow_event_date') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
