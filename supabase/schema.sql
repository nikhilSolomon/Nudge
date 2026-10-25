-- Nudge sync schema. Run once in the Supabase SQL editor (Dashboard → SQL → New query → Run).
-- One row per todo, owned by the signed-in user. Deletes are tombstones (deleted_at) so they sync.

create table if not exists public.todos (
  id            uuid primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title         text not null,
  notes         text not null default '',
  is_done       boolean not null default false,
  created_at    timestamptz not null default now(),
  completed_at  timestamptz,
  reminder_at   timestamptz,
  repeat_rule   text not null default 'none',
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index if not exists todos_user_updated_idx on public.todos (user_id, updated_at);

alter table public.todos enable row level security;

drop policy if exists "todos: owner can do everything" on public.todos;
create policy "todos: owner can do everything"
  on public.todos
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Optional: purge tombstones older than 60 days (run manually or via pg_cron).
-- delete from public.todos where deleted_at is not null and deleted_at < now() - interval '60 days';

-- synced_at: when the row last reached the server (set by trigger, not by clients).
-- Clients pull by synced_at so rows edited offline / long ago are never missed.
alter table public.todos add column if not exists synced_at timestamptz not null default now();

create or replace function public.todos_set_synced_at()
returns trigger language plpgsql as $$
begin
  new.synced_at = now();
  return new;
end $$;

drop trigger if exists todos_set_synced_at on public.todos;
create trigger todos_set_synced_at
  before insert or update on public.todos
  for each row execute function public.todos_set_synced_at();

create index if not exists todos_user_synced_idx on public.todos (user_id, synced_at);
