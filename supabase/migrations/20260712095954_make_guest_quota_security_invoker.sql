-- The Render API already verifies both the Supabase access token and the
-- is_anonymous claim before calling this routine. The routine therefore only
-- needs the service role's table privilege; it does not need to run with the
-- database owner's privileges or read auth.users.

create or replace function public.consume_guest_query(target_user_id uuid)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_count integer;
begin
  insert into public.guest_usage as usage (user_id, query_count, updated_at)
  values (target_user_id, 1, now())
  on conflict (user_id) do update
    set query_count = usage.query_count + 1,
        updated_at = now()
  returning query_count into new_count;

  return new_count;
end;
$$;

revoke all on function public.consume_guest_query(uuid)
  from public, anon, authenticated;
grant execute on function public.consume_guest_query(uuid) to service_role;
