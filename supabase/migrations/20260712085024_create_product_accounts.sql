-- Account-backed chat persistence for Nakul.
-- The Flutter client uses the Data API with a publishable key; RLS is the
-- authorization boundary and every row is scoped to auth.uid().

create table public.conversations (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  payload jsonb not null default '[]'::jsonb,
  bookmarked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversations_id_format check (
    id ~ '^c_[A-Za-z0-9_-]{8,100}$'
  ),
  constraint conversations_title_length check (
    char_length(title) between 1 and 120
  ),
  constraint conversations_payload_array check (
    jsonb_typeof(payload) = 'array'
  ),
  constraint conversations_payload_size check (
    octet_length(payload::text) <= 5242880
  )
);

create index conversations_user_updated_idx
  on public.conversations (user_id, updated_at desc);

alter table public.conversations enable row level security;
alter table public.conversations force row level security;

create policy "Users can read their own conversations"
  on public.conversations
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can create their own conversations"
  on public.conversations
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update their own conversations"
  on public.conversations
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can delete their own conversations"
  on public.conversations
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.conversations from anon;
grant select, insert, update, delete on table public.conversations to authenticated;
grant all on table public.conversations to service_role;

create table public.product_events (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  properties jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint product_events_name_format check (
    name ~ '^[a-z][a-z0-9_]{1,63}$'
  ),
  constraint product_events_properties_object check (
    jsonb_typeof(properties) = 'object'
  ),
  constraint product_events_properties_size check (
    octet_length(properties::text) <= 16384
  )
);

create index product_events_user_created_idx
  on public.product_events (user_id, created_at desc);

alter table public.product_events enable row level security;
alter table public.product_events force row level security;

-- Product events are write-only from the app. Reading and retention jobs use
-- server-side roles, keeping one user's behavior invisible to every client.
create policy "Users can record their own product events"
  on public.product_events
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on table public.product_events from anon;
grant insert on table public.product_events to authenticated;
grant usage, select on sequence public.product_events_id_seq to authenticated;
grant all on table public.product_events to service_role;
grant all on sequence public.product_events_id_seq to service_role;
