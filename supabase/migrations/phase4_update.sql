-- Phase 4 update: shared loans. Run once in the Supabase SQL editor after
-- phase3_update.sql. Safe to run more than once.

-- 1. Invites. A lender invites the borrower of a loan with a short code.
--    The code is single-use and expires after 7 days.
create table if not exists invites (
  code text primary key,
  group_id uuid not null references groups on delete cascade,
  contact_id uuid not null references contacts on delete cascade,
  created_by uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by uuid references profiles,
  used_at timestamptz
);
alter table invites enable row level security;
-- The lender can see their own invites. Nobody can read other people's codes,
-- and invites are created and used only through the two functions below.
drop policy if exists invites_read on invites;
create policy invites_read on invites for select using (created_by = auth.uid());

-- Makes (or returns the still-valid) invite code for the borrower of a loan.
create or replace function create_invite(p_loan_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  l loans%rowtype;
  v_code text;
begin
  select * into l from loans
  where id = p_loan_id and status = 'active'
    and lender_user_id = auth.uid()      -- only the lender invites
    and borrower_user_id is null         -- the borrower has not joined yet
    and contact_id is not null;
  if not found then
    raise exception 'INVITE_NOT_ALLOWED';
  end if;

  select code into v_code from invites
  where group_id = l.group_id and contact_id = l.contact_id and created_by = auth.uid()
    and used_at is null and expires_at > now()
  order by created_at desc limit 1;
  if v_code is not null then
    return v_code;
  end if;

  -- 10 random characters (0-9, A-F) from a random UUID.
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into invites (code, group_id, contact_id, created_by)
  values (v_code, l.group_id, l.contact_id, auth.uid());
  return v_code;
end $$;

-- The borrower uses a code: they become the borrower on that person's loans in
-- the group, join the group, and the lender's contact is linked to their account.
-- Returns one of the loans so the app can open it.
create or replace function join_with_code(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  inv invites%rowtype;
  v_loan uuid;
begin
  if auth.uid() is null then
    raise exception 'INVITE_INVALID';
  end if;
  select * into inv from invites
  where code = upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'))
    and used_at is null and expires_at > now()
  for update;
  if not found then
    raise exception 'INVITE_INVALID';
  end if;
  if inv.created_by = auth.uid() then
    raise exception 'INVITE_OWN';
  end if;

  update loans set borrower_user_id = auth.uid()
  where group_id = inv.group_id and contact_id = inv.contact_id
    and lender_user_id = inv.created_by and borrower_user_id is null;
  if not found then
    raise exception 'INVITE_INVALID';
  end if;

  insert into group_members (group_id, user_id, role)
  values (inv.group_id, auth.uid(), 'borrower')
  on conflict do nothing;
  update contacts set linked_user_id = auth.uid() where id = inv.contact_id;
  update invites set used_by = auth.uid(), used_at = now() where code = inv.code;

  select id into v_loan from loans
  where group_id = inv.group_id and contact_id = inv.contact_id and borrower_user_id = auth.uid()
  order by created_at limit 1;
  return v_loan;
end $$;

-- 2. Names of the two sides of each loan the caller can see. Needed because a
--    borrower cannot read the lender's contacts or profile directly.
--    When the lender is on the app, the contact is the borrower. In solo
--    borrower mode (no lender account) the contact is the lender.
create or replace function loan_people()
returns table (loan_id uuid, lender_name text, borrower_name text)
language sql stable security definer set search_path = public as $$
  select l.id,
    case when l.lender_user_id is not null then lp.name else c.name end,
    case when l.lender_user_id is not null then c.name else bp.name end
  from loans l
  left join profiles lp on lp.id = l.lender_user_id
  left join profiles bp on bp.id = l.borrower_user_id
  left join contacts c on c.id = l.contact_id
  where auth.uid() in (l.created_by, l.lender_user_id, l.borrower_user_id) $$;

-- 3. create_loan gains "I am the borrower" (solo borrower mode: a loan the
--    caller took from someone who is not on the app).
drop function if exists create_loan(uuid, uuid, bigint, date, date, int, text, text, int, int);
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
  p_grace_days int,
  p_i_am_borrower boolean default false
) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  new_id uuid;
begin
  if not exists (select 1 from contacts where id = p_contact_id and owner_id = auth.uid()) then
    raise exception 'Borrower not found';
  end if;
  if p_next_due_date is not null and p_next_due_date < p_start_date then
    raise exception 'Due date is before the start date';
  end if;

  insert into loans (group_id, created_by, lender_user_id, borrower_user_id, contact_id,
                     principal_paise, start_date, next_due_date)
  values (p_group_id, auth.uid(),
          case when p_i_am_borrower then null else auth.uid() end,
          case when p_i_am_borrower then auth.uid() else null end,
          p_contact_id, p_principal_paise, p_start_date, p_next_due_date)
  returning id into new_id;

  insert into loan_terms (loan_id, version, rate_bps, rate_period, interest_type,
                          late_rate_bps, grace_days, created_by)
  values (new_id, 1, p_rate_bps, p_rate_period, p_interest_type,
          p_late_rate_bps, p_grace_days, auth.uid());
  return new_id;
end $$;

-- 4. Only the borrower of a shared loan can confirm, and only payments.
drop policy if exists confirm_insert on entry_confirmations;
create policy confirm_insert on entry_confirmations for insert with check (
  user_id = auth.uid()
  and exists (
    select 1 from ledger_entries e join loans l on l.id = e.loan_id
    where e.id = entry_id and e.kind = 'payment'
      and l.borrower_user_id = auth.uid() and l.lender_user_id is not null));

-- 5. From the app, a lender may change only a loan's due date and status
--    (close it). The amount, the dates already set and who the two sides are
--    cannot be edited. Database functions (invites) are not affected.
create or replace function guard_loan_update() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and (
       new.group_id is distinct from old.group_id
    or new.created_by is distinct from old.created_by
    or new.lender_user_id is distinct from old.lender_user_id
    or new.borrower_user_id is distinct from old.borrower_user_id
    or new.contact_id is distinct from old.contact_id
    or new.principal_paise is distinct from old.principal_paise
    or new.start_date is distinct from old.start_date
    or new.created_at is distinct from old.created_at) then
    raise exception 'Only the due date and status of a loan can be changed.';
  end if;
  return new;
end $$;
drop trigger if exists loans_guard_update on loans;
create trigger loans_guard_update before update on loans
for each row execute function guard_loan_update();

-- 6. Realtime: both phones refresh when the loan changes.
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['ledger_entries', 'loans', 'loan_terms', 'entry_confirmations'] loop
      begin
        execute format('alter publication supabase_realtime add table %I', t);
      exception when duplicate_object then null;
      end;
    end loop;
  end if;
end $$;
