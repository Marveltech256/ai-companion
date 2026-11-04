alter table public.profiles add column timezone_automatic boolean not null default false,
 add column reply_mode text not null default 'text' check(reply_mode in ('text','voice'));

create function public.morrow_save_friend_introduction(p_owner text,p_age_group text,p_language text,p_timezone text,p_automatic boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 perform public.morrow_save_introduction(p_owner,p_age_group,p_language,p_timezone);
 if p_automatic is null then raise exception 'invalid_input'; end if;
 update public.profiles set timezone_automatic=p_automatic where user_id=p_owner returning to_jsonb(profiles.*) into result;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_save_timezone(p_owner text,p_timezone text,p_automatic boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if p_automatic is null or p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'invalid_input'; end if;
 update public.profiles set timezone=p_timezone,timezone_automatic=p_automatic,updated_at=now()
 where user_id=p_owner returning to_jsonb(profiles.*) into result;
 if result is null then raise exception 'not_found'; end if;
 return jsonb_build_object('profile',result);
end; $$;

create function public.morrow_reply_mode(p_owner text,p_mode text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if p_mode is null or p_mode not in ('text','voice') then raise exception 'invalid_input'; end if;
 update public.profiles set reply_mode=p_mode,updated_at=now() where user_id=p_owner returning to_jsonb(profiles.*) into result;
 if result is null then raise exception 'not_found'; end if;
 return jsonb_build_object('profile',result);
end; $$;

-- Called only after the client explicitly accepts personal companion mode.
-- Existing opt-outs are never silently converted into consent by migration.
create function public.morrow_activate_friend_mode(p_owner text,p_companion uuid,p_consent boolean)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare c public.companions;result jsonb;
begin
 if p_consent is distinct from true then raise exception 'consent_required'; end if;
 perform public.morrow_require_eligible(p_owner);
 select * into c from public.companions where owner_id=p_owner and id=p_companion for update;
 if not found then raise exception 'not_found'; end if;
 perform public.morrow_save_companion(p_owner,c.name,c.communication_style,c.interests,c.response_length,true,c.retention_days);
 result=public.morrow_set_learning(p_owner,p_companion,true);
 return result;
end; $$;

create function public.morrow_require_friend_mode(p_owner text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 perform public.morrow_require_eligible(p_owner);
 if not exists(select 1 from public.companions where owner_id=p_owner and memory_enabled and learning_enabled)
 then raise exception 'personal_companion_required'; end if;
 return jsonb_build_object('ok',true);
end; $$;

do $$ declare fn regprocedure; begin
 for fn in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in (
  'morrow_save_friend_introduction','morrow_save_timezone','morrow_reply_mode','morrow_activate_friend_mode','morrow_require_friend_mode') loop
  execute format('revoke all on function %s from public,anon,authenticated',fn);
  execute format('grant execute on function %s to service_role',fn);
 end loop;
end; $$;
