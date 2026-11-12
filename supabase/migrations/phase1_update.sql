-- Phase 1 update. Run this ONLY if you already ran an earlier version of the schema.
-- If you are running supabase/schema.sql fresh, you do not need this file.
-- Safe to run more than once.

-- 1. Save the language chosen at sign-up on the new profile row.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
insert into profiles (id, name, language) values (
new.id,
coalesce(new.raw_user_meta_data->>'name',''),
case when new.raw_user_meta_data->>'language' in ('en','te','hi')
then new.raw_user_meta_data->>'language' else 'en' end);
return new;
end $$;

-- 2. The one-line loans policy fix: read loans by checking columns directly,
--    so a new loan can be read back right after insert.
drop policy if exists loans_read on loans;
create policy loans_read on loans for select using (auth.uid() in (created_by, lender_user_id, borrower_user_id));
