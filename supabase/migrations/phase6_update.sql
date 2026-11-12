-- Phase 6 update: problem reports from testers. Run once in the Supabase SQL
-- editor after phase5_update.sql. Safe to run more than once.

-- Testers send a short note from Settings → Report a problem. You read them in
-- the Supabase dashboard (Table editor → feedback), newest first:
--   select f.created_at, p.name, f.app_version, f.message
--   from feedback f join profiles p on p.id = f.user_id order by f.created_at desc;
create table if not exists feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles on delete cascade,
  message text not null check (char_length(message) between 1 and 2000),
  app_version text,
  created_at timestamptz not null default now()
);
alter table feedback enable row level security;
-- People can send reports but cannot read anyone's reports back (not even
-- their own): only the owner sees them, in the dashboard.
drop policy if exists feedback_insert on feedback;
create policy feedback_insert on feedback for insert with check (user_id = auth.uid());
