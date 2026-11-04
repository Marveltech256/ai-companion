-- Additive moderation queue. Existing conversations and settings are untouched.
create table public.content_reports (
 id uuid primary key default gen_random_uuid(),
 owner_id text not null references public.profiles(user_id) on delete cascade,
 request_id uuid not null,
 message_id uuid references public.messages(id) on delete set null,
 message_snapshot text not null check(length(message_snapshot) between 1 and 12000),
 reason text not null check(reason in ('unsafe','inaccurate','other')),
 details text not null default '' check(length(details)<=2000),
 status text not null default 'new' check(status in ('new','reviewed','action_taken','dismissed')),
 created_at timestamptz not null default now(), reviewed_at timestamptz,
 unique(owner_id,request_id)
);
create index content_reports_review on public.content_reports(status,created_at);
alter table public.content_reports enable row level security;
revoke all on public.content_reports from anon,authenticated;
grant all on public.content_reports to service_role;
-- Only the verified API returns a receipt. Snapshots and moderation queues are
-- not directly exposed to browser/mobile database clients.
create function public.morrow_report_message(p_owner text,p_request uuid,p_message uuid,p_reason text,p_details text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.content_reports; snapshot text;
begin
 if p_request is null or p_reason is null or p_reason not in ('unsafe','inaccurate','other')
  or p_details is null or length(p_details)>2000 then raise exception 'invalid_input'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 select * into r from public.content_reports where owner_id=p_owner and request_id=p_request;
 if found then
  if r.message_id is distinct from p_message or r.reason<>p_reason or r.details<>p_details then raise exception 'request_conflict'; end if;
  return jsonb_build_object('report',jsonb_build_object('id',r.id,'status',r.status));
 end if;
 select m.content into snapshot from public.messages m join public.conversations c on c.id=m.conversation_id and c.owner_id=m.owner_id
  where m.id=p_message and m.owner_id=p_owner and m.role='assistant' and m.status='completed';
 if snapshot is null or snapshot='' then raise exception 'not_found'; end if;
 if (select count(*) from public.content_reports where owner_id=p_owner and created_at>now()-interval '1 day')>=20 then raise exception 'rate_limited'; end if;
 insert into public.content_reports(owner_id,request_id,message_id,message_snapshot,reason,details)
  values(p_owner,p_request,p_message,snapshot,p_reason,p_details) returning * into r;
 return jsonb_build_object('report',jsonb_build_object('id',r.id,'status',r.status));
end; $$;

create function public.morrow_review_report(p_report uuid,p_status text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_status is null or p_status not in ('reviewed','action_taken','dismissed') then raise exception 'invalid_input'; end if;
 update public.content_reports set status=p_status,reviewed_at=now() where id=p_report;
 if not found then raise exception 'not_found'; end if;
 return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_report_export(p_owner text,p_after text default '')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare rows jsonb;begin
 if exists(select 1 from public.account_deletions where owner_id=p_owner) then raise exception 'account_deleted'; end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') into rows from
  (select id,message_id,message_snapshot,reason,details,status,created_at,reviewed_at from public.content_reports
   where owner_id=p_owner and id::text>p_after order by id limit 201)r;
 return jsonb_build_object('section','reports','rows',coalesce((select jsonb_agg(value) from jsonb_array_elements(rows) with ordinality e(value,n) where n<=200),'[]'),
  'next_cursor',case when jsonb_array_length(rows)>200 then rows->199->>'id' else null end);
end; $$;

create function public.morrow_report_cleanup() returns jsonb language plpgsql security invoker set search_path='' as $$
begin delete from public.content_reports where created_at<now()-interval '90 days'; return jsonb_build_object('ok',true);end; $$;
do $$ declare fn regprocedure;begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in
  ('morrow_report_message','morrow_review_report','morrow_report_export','morrow_report_cleanup') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
