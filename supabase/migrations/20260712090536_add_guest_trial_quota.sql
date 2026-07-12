-- Server-owned quota for the frictionless anonymous trial. Clients have no
-- privileges on this table or function; Render consumes one slot after it has
-- authenticated the Supabase user token.

create table public.guest_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  query_count integer not null default 0,
  updated_at timestamptz not null default now(),
  constraint guest_usage_nonnegative check (query_count >= 0)
);

alter table public.guest_usage enable row level security;
alter table public.guest_usage force row level security;

revoke all on table public.guest_usage from public, anon, authenticated;
grant all on table public.guest_usage to service_role;

create or replace function public.consume_guest_query(target_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  is_guest boolean;
  new_count integer;
begin
  select users.is_anonymous
    into is_guest
    from auth.users as users
   where users.id = target_user_id;

  if coalesce(is_guest, false) is false then
    return 0;
  end if;

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
