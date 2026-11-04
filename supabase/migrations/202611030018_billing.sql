-- Billing is OFF. Adding infrastructure never starts a trial, sells a product,
-- charges a customer or changes existing free-testing access.
create table public.billing_configuration (
 singleton boolean primary key default true check(singleton),
 sales_enabled boolean not null default false,
 enforcement_enabled boolean not null default false,
 monthly_product_id text, monthly_base_plan_id text,
 intro_days integer check(intro_days between 0 and 90),
 free_daily_messages integer check(free_daily_messages between 1 and 10000),
 premium_daily_messages integer check(premium_daily_messages between 1 and 10000),
 free_daily_voice integer check(free_daily_voice between 0 and 20),
 premium_daily_voice integer check(premium_daily_voice between 0 and 20),
 check(not sales_enabled or (monthly_product_id is not null and monthly_base_plan_id is not null
  and length(monthly_product_id)>0 and length(monthly_base_plan_id)>0)),
 check(not enforcement_enabled or (sales_enabled and intro_days is not null and free_daily_messages is not null
  and premium_daily_messages is not null and free_daily_voice is not null and premium_daily_voice is not null))
);
insert into public.billing_configuration(singleton) values(true);
create table public.billing_accounts (
 owner_id text primary key references public.profiles(user_id) on delete cascade,
 account_ref uuid not null unique default gen_random_uuid(), intro_started_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.subscriptions (
 id uuid primary key default gen_random_uuid(),
 owner_id text not null references public.profiles(user_id) on delete cascade,
 token_hash text not null unique check(token_hash~'^[0-9a-f]{64}$'),
 encrypted_token text not null check(length(encrypted_token) between 1 and 16000),
 product_id text not null, base_plan_id text not null,
 state text not null check(state in ('pending','active','grace','canceled','expired','paused','hold','revoked')),
 expires_at timestamptz, acknowledged boolean not null default false, auto_renew boolean not null default false,
 verified_at timestamptz not null, created_at timestamptz not null default now()
);
create index subscriptions_owner on public.subscriptions(owner_id,expires_at desc);
create table public.billing_usage (
 owner_id text not null references public.profiles(user_id) on delete cascade,
 operation_id uuid not null, kind text not null check(kind in ('chat','greeting','voice','verification')),
 created_at timestamptz not null default now(), primary key(owner_id,operation_id,kind)
);
create index billing_usage_window on public.billing_usage(owner_id,created_at desc);
do $$ declare t text;begin
 foreach t in array array['billing_configuration','billing_accounts','subscriptions','billing_usage'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end; $$;

create function public.morrow_billing_status(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare c public.billing_configuration; a public.billing_accounts; s public.subscriptions;
 mode text='free_testing'; trial_end timestamptz; chat_used integer; voice_used integer;
begin
 if not exists(select 1 from public.profiles where user_id=p_owner) then raise exception 'not_found'; end if;
 select * into c from public.billing_configuration where singleton;
 if not c.sales_enabled and not c.enforcement_enabled then
  return jsonb_build_object('mode',mode,'available',false,'enforced',false,'premium',false);
 end if;
 insert into public.billing_accounts(owner_id) values(p_owner) on conflict do nothing;
 if c.enforcement_enabled then update public.billing_accounts set intro_started_at=coalesce(intro_started_at,now()) where owner_id=p_owner; end if;
 select * into a from public.billing_accounts where owner_id=p_owner;
 select * into s from public.subscriptions where owner_id=p_owner and acknowledged
  and state in ('active','grace','canceled') and expires_at>now() and verified_at>now()-interval '24 hours'
  order by expires_at desc limit 1;
 trial_end=a.intro_started_at+make_interval(days=>c.intro_days);
 if s.id is not null then mode='premium';
 elsif c.enforcement_enabled then mode=case when trial_end>now() then 'introductory' else 'expired' end; end if;
 select count(*) filter(where kind in ('chat','greeting')),count(*) filter(where kind='voice') into chat_used,voice_used
  from public.billing_usage where owner_id=p_owner and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
 return jsonb_build_object('mode',mode,'available',c.sales_enabled,'enforced',c.enforcement_enabled,'premium',s.id is not null,
  'account_ref',a.account_ref,'product_id',c.monthly_product_id,'base_plan_id',c.monthly_base_plan_id,
  'trial_ends_at',trial_end,'expires_at',s.expires_at,'auto_renew',s.auto_renew,
  'messages_used_today',chat_used,'voice_requests_used_today',voice_used,
  'messages_limit',case when s.id is not null then c.premium_daily_messages else c.free_daily_messages end,
  'voice_limit',case when s.id is not null then c.premium_daily_voice else c.free_daily_voice end);
end; $$;

create function public.morrow_billing_attempt(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 if (select count(*) from public.billing_usage where owner_id=p_owner and kind='verification' and created_at>now()-interval '1 minute')>=10 then raise exception 'rate_limited'; end if;
 insert into public.billing_usage(owner_id,operation_id,kind) values(p_owner,gen_random_uuid(),'verification');
 return jsonb_build_object('ok',true);
end; $$;

create function public.morrow_apply_subscription(p_owner text,p_account_ref uuid,p_token_hash text,p_linked_hash text,
 p_encrypted_token text,p_product text,p_base_plan text,p_state text,p_expires timestamptz,p_acknowledged boolean,p_auto_renew boolean,p_verified_at timestamptz)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare existing public.subscriptions; c public.billing_configuration;
begin
 select * into c from public.billing_configuration where singleton;
 if not c.sales_enabled then raise exception 'billing_unavailable'; end if;
 if p_product is distinct from c.monthly_product_id or p_base_plan is distinct from c.monthly_base_plan_id
  or not exists(select 1 from public.billing_accounts where owner_id=p_owner and account_ref=p_account_ref)
  or p_verified_at is null or p_verified_at>now()+interval '1 minute' or p_verified_at<now()-interval '5 minutes'
  then raise exception 'invalid_purchase'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_token_hash,1));
 select * into existing from public.subscriptions where token_hash=p_token_hash;
 if existing.id is not null and existing.owner_id<>p_owner then raise exception 'purchase_conflict'; end if;
 if p_linked_hash is not null and exists(select 1 from public.subscriptions where token_hash=p_linked_hash and owner_id<>p_owner)
  then raise exception 'purchase_conflict'; end if;
 -- An older HTTP/provider response cannot undo a later verified lifecycle update.
 if existing.verified_at is not null and existing.verified_at>p_verified_at then return public.morrow_billing_status(p_owner); end if;
 if existing.state='revoked' and p_state<>'revoked' then return public.morrow_billing_status(p_owner); end if;
 insert into public.subscriptions(owner_id,token_hash,encrypted_token,product_id,base_plan_id,state,expires_at,acknowledged,auto_renew,verified_at)
 values(p_owner,p_token_hash,p_encrypted_token,p_product,p_base_plan,p_state,p_expires,p_acknowledged,p_auto_renew,p_verified_at)
 on conflict(token_hash) do update set encrypted_token=excluded.encrypted_token,product_id=excluded.product_id,
  base_plan_id=excluded.base_plan_id,state=excluded.state,expires_at=excluded.expires_at,acknowledged=excluded.acknowledged,
  auto_renew=excluded.auto_renew,verified_at=excluded.verified_at;
 if p_linked_hash is not null and p_linked_hash<>p_token_hash then
  update public.subscriptions set state='revoked',expires_at=least(expires_at,now()),verified_at=p_verified_at
   where token_hash=p_linked_hash and owner_id=p_owner and verified_at<=p_verified_at;
 end if;
 return public.morrow_billing_status(p_owner);
end; $$;

create function public.morrow_subscription_tokens(p_owner text) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('subscriptions',coalesce(jsonb_agg(to_jsonb(s)),'[]')) from
 (select token_hash,encrypted_token from public.subscriptions where owner_id=p_owner and state<>'revoked' order by verified_at desc limit 3)s;
$$;
create function public.morrow_subscription_owner(p_hash text) returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('owner',owner_id) from public.subscriptions where token_hash=p_hash;
$$;

create function public.morrow_invalidate_subscription(p_owner text,p_hash text,p_verified_at timestamptz) returns jsonb
language plpgsql security invoker set search_path='' as $$
begin
 if p_verified_at is null or p_verified_at>now()+interval '1 minute' or p_verified_at<now()-interval '5 minutes' then raise exception 'invalid_input'; end if;
 update public.subscriptions set state='revoked',expires_at=least(coalesce(expires_at,now()),now()),auto_renew=false,verified_at=p_verified_at
  where owner_id=p_owner and token_hash=p_hash and verified_at<=p_verified_at;
 return public.morrow_billing_status(p_owner);
end; $$;

create function public.morrow_reserve_usage(p_owner text,p_operation uuid,p_kind text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare s jsonb; used integer; cap integer;
begin
 if not (select enforcement_enabled from public.billing_configuration where singleton) then return jsonb_build_object('ok',true); end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner,0));
 s=public.morrow_billing_status(p_owner);
 if s->>'mode'='expired' then raise exception 'subscription_required'; end if;
 if exists(select 1 from public.billing_usage where owner_id=p_owner and operation_id=p_operation and kind=p_kind) then return jsonb_build_object('ok',true); end if;
 if p_kind in ('chat','greeting') then cap=(s->>'messages_limit')::integer;used=(s->>'messages_used_today')::integer;
 elsif p_kind='voice' then cap=(s->>'voice_limit')::integer;used=(s->>'voice_requests_used_today')::integer;
 else raise exception 'invalid_input';end if;
 if cap is null or used>=cap then raise exception 'usage_limit'; end if;
 insert into public.billing_usage(owner_id,operation_id,kind) values(p_owner,p_operation,p_kind);
 return jsonb_build_object('ok',true);
end; $$;
create function public.morrow_access_begin_turn(p_owner text,p_conversation uuid,p_request uuid,p_content text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;begin
 result=public.morrow_begin_turn(p_owner,p_conversation,p_request,p_content);
 if result->>'status'='running' then perform public.morrow_reserve_usage(p_owner,coalesce((result->>'request_id')::uuid,p_request),'chat');end if;
 return result;
end; $$;
create function public.morrow_access_begin_greeting(p_owner text,p_conversation uuid,p_request uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;begin
 result=public.morrow_begin_greeting(p_owner,p_conversation,p_request);
 if result->>'status'='running' then perform public.morrow_reserve_usage(p_owner,coalesce((result->>'request_id')::uuid,p_request),'greeting');end if;
 return result;
end; $$;
create function public.morrow_access_voice(p_owner text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;begin
 result=public.morrow_authorize_voice(p_owner);perform public.morrow_reserve_usage(p_owner,gen_random_uuid(),'voice');return result;
end; $$;

create function public.morrow_billing_export(p_owner text,p_section text,p_after text default '') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare rows jsonb;begin
 if exists(select 1 from public.account_deletions where owner_id=p_owner) then raise exception 'account_deleted';end if;
 if p_section='subscriptions' then
  select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') into rows from (select id,product_id,base_plan_id,state,expires_at,acknowledged,auto_renew,verified_at,created_at
   from public.subscriptions where owner_id=p_owner and id::text>p_after order by id limit 201)s;
 elsif p_section='usage' then
  select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') into rows from (select operation_id::text||kind as id,kind,created_at
   from public.billing_usage where owner_id=p_owner and operation_id::text||kind>p_after order by operation_id::text||kind limit 201)s;
 else raise exception 'invalid_input';end if;
 return jsonb_build_object('section',p_section,'rows',coalesce((select jsonb_agg(value) from jsonb_array_elements(rows) with ordinality e(value,n) where n<=200),'[]'),
  'next_cursor',case when jsonb_array_length(rows)>200 then rows->199->>'id' else null end);
end; $$;
create function public.morrow_billing_cleanup() returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 delete from public.billing_usage where created_at<now()-interval '90 days';
 delete from public.subscriptions where expires_at<now()-interval '90 days' and state in ('expired','revoked');
 return jsonb_build_object('ok',true);
end; $$;
do $$ declare fn regprocedure;begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in
 ('morrow_billing_status','morrow_billing_attempt','morrow_apply_subscription','morrow_subscription_tokens','morrow_subscription_owner','morrow_invalidate_subscription',
 'morrow_reserve_usage','morrow_access_begin_turn','morrow_access_begin_greeting','morrow_access_voice','morrow_billing_export','morrow_billing_cleanup') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
