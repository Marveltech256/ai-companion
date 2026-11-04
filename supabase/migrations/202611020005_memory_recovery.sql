create function public.morrow_pending_memory_jobs(p_owner text)
returns jsonb language sql security invoker set search_path='' as $$
  select jsonb_build_object('requests',coalesce(jsonb_agg(request_id),'[]'::jsonb)) from (
    select request_id from public.memory_jobs where owner_id=p_owner and attempts<5
      and (status in ('pending','failed') or (status='running' and lease_until<now()))
    order by created_at limit 3)j;
$$;
revoke all on function public.morrow_pending_memory_jobs(text) from public,anon,authenticated;
grant execute on function public.morrow_pending_memory_jobs(text) to service_role;
