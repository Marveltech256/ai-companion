-- Local additive candidate; reconcile target migrations before deployment.
alter table public.profiles add column username text
 check(username is null or username ~ '^[a-z0-9][a-z0-9_]{2,29}$');
create unique index unique_profile_username on public.profiles(lower(username)) where username is not null;

create function public.morrow_save_named_profile(p_owner text,p_username text,p_preferred_name text,p_display_name text,
 p_timezone text,p_language text,p_location text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;handle text=nullif(lower(btrim(p_username)),'');
begin
 if handle is not null and handle !~ '^[a-z0-9][a-z0-9_]{2,29}$' then raise exception 'invalid_username'; end if;
 if handle is not null and (p_preferred_name is null or length(btrim(p_preferred_name)) not between 1 and 80) then raise exception 'invalid_input'; end if;
 perform public.morrow_save_personal_profile(p_owner,p_preferred_name,p_display_name,p_timezone,p_language,p_location);
 update public.profiles set username=handle where user_id=p_owner returning to_jsonb(profiles.*) into result;
 return jsonb_build_object('profile',result);
exception when unique_violation then raise exception 'username_taken';
end; $$;
revoke all on function public.morrow_save_named_profile(text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.morrow_save_named_profile(text,text,text,text,text,text,text) to service_role;
