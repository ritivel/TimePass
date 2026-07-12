-- Conversation ids originate on-device. Scoping uniqueness to the owner lets
-- an anonymous user's locally handed-off conversation ids be copied into an
-- existing permanent account without colliding with the still-live guest row.

alter table public.conversations
  drop constraint conversations_pkey;

alter table public.conversations
  add constraint conversations_pkey primary key (user_id, id);

create index conversations_id_idx on public.conversations (id);
