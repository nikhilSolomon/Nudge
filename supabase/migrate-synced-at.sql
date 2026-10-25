-- Run this once if you created the table before synced_at existed.
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
