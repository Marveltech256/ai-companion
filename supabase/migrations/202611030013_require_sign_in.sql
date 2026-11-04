-- Registered Firebase accounts are required for every client read policy.
-- Existing guest data is retained so its account can still be linked at signup.
create or replace function public.morrow_authenticated_owner() returns text
language sql stable security definer set search_path='' as $$
select case when (auth.jwt()->>'iss')='https://securetoken.google.com/'||c.firebase_project_id
 and (auth.jwt()->'firebase'->>'tenant') is null
 and coalesce(auth.jwt()->'firebase'->>'sign_in_provider','') not in ('','anonymous')
 and not exists(select 1 from public.account_deletions d where d.owner_id=auth.jwt()->>'sub')
 then auth.jwt()->>'sub' else null end from public.identity_configuration c where c.singleton;
$$;
revoke all on function public.morrow_authenticated_owner() from public,anon;
grant execute on function public.morrow_authenticated_owner() to authenticated,service_role;
notify pgrst,'reload schema';
