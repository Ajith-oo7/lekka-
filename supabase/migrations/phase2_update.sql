-- Phase 2 update. Run once in the Supabase SQL editor (after schema.sql and,
-- if you needed it, phase1_update.sql). Safe to run more than once.

-- 1. Create a loan and its first terms version in ONE transaction, so a loan
--    can never exist without terms. Runs as the signed-in person
--    (security invoker), so every Row Level Security policy still applies:
--    only the group owner can add a loan to the group.
create or replace function create_loan(
  p_group_id uuid,
  p_contact_id uuid,
  p_principal_paise bigint,
  p_start_date date,
  p_next_due_date date,
  p_rate_bps int,
  p_rate_period text,
  p_interest_type text,
  p_late_rate_bps int,
  p_grace_days int
) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  new_id uuid;
begin
  -- The borrower must be one of the caller's own contacts.
  if not exists (select 1 from contacts where id = p_contact_id and owner_id = auth.uid()) then
    raise exception 'Borrower not found';
  end if;
  if p_next_due_date is not null and p_next_due_date < p_start_date then
    raise exception 'Due date is before the start date';
  end if;

  insert into loans (group_id, created_by, lender_user_id, contact_id,
                     principal_paise, start_date, next_due_date)
  values (p_group_id, auth.uid(), auth.uid(), p_contact_id,
          p_principal_paise, p_start_date, p_next_due_date)
  returning id into new_id;
  -- Trigger loan_created_log adds the 'Loan given' record.

  insert into loan_terms (loan_id, version, rate_bps, rate_period, interest_type,
                          late_rate_bps, grace_days, created_by)
  values (new_id, 1, p_rate_bps, p_rate_period, p_interest_type,
          p_late_rate_bps, p_grace_days, auth.uid());
  -- Trigger terms_change_log adds the 'Terms updated' record.

  return new_id;
end $$;

-- 2. A record can be corrected only once.
create unique index if not exists one_reversal_per_entry
  on ledger_entries (reverses_id) where reverses_id is not null;

-- 3. Edits and deletes of Records from the app now fail with the clear
--    "Records cannot be changed" error instead of silently changing nothing.
--    These policies only let the request reach the ledger_append_only trigger,
--    which rejects every update and delete.
drop policy if exists ledger_update_blocked on ledger_entries;
create policy ledger_update_blocked on ledger_entries for update using (can_see_loan(loan_id));
drop policy if exists ledger_delete_blocked on ledger_entries;
create policy ledger_delete_blocked on ledger_entries for delete using (can_see_loan(loan_id));

-- 4. Tidy the stored note for terms: "10.00%" instead of "10.0000000000000000%".
create or replace function log_terms_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
insert into ledger_entries (loan_id, kind, amount_paise, created_by, note)
values (new.loan_id, 'terms_change', 0, new.created_by,
'Terms v' || new.version || ': ' || to_char(new.rate_bps / 100.0, 'FM999990.00') || '% per ' || new.rate_period
|| ', ' || new.interest_type || ', late +' || to_char(new.late_rate_bps / 100.0, 'FM999990.00') || '%');
return new;
end $$;
