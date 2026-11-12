-- Lekka database schema (from the build prompt, section 7).
-- Run once in the Supabase SQL editor. Money is paise. Rates are basis points (1000 = 10.00%).
-- Phase 1 change: handle_new_user also saves the language chosen at sign-up.

create extension if not exists pgcrypto;
create table profiles (
id uuid primary key references auth.users on delete cascade,
name text not null default '',
language text not null default 'en' check (language in ('en','te','hi')),
created_at timestamptz not null default now()
);
create table contacts (
id uuid primary key default gen_random_uuid(),
owner_id uuid not null references profiles on delete cascade,
name text not null,
phone text,
linked_user_id uuid references profiles,
created_at timestamptz not null default now()
);
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
-- Name and language come from the sign-up form (user metadata).
-- An unknown or missing language falls back to English.
insert into profiles (id, name, language) values (
new.id,
coalesce(new.raw_user_meta_data->>'name',''),
case when new.raw_user_meta_data->>'language' in ('en','te','hi')
then new.raw_user_meta_data->>'language' else 'en' end);
return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function handle_new_user();
create table groups (
id uuid primary key default gen_random_uuid(),
owner_id uuid not null references profiles on delete cascade,
name text not null,
created_at timestamptz not null default now()
);
create table group_members (
group_id uuid not null references groups on delete cascade,
user_id uuid not null references profiles on delete cascade,
role text not null check (role in ('lender','borrower')),
primary key (group_id, user_id)
);
create table loans (
id uuid primary key default gen_random_uuid(),
group_id uuid not null references groups,
created_by uuid not null references profiles,
lender_user_id uuid references profiles,
borrower_user_id uuid references profiles,
contact_id uuid references contacts,
principal_paise bigint not null check (principal_paise > 0),
start_date date not null default current_date,
next_due_date date,
status text not null default 'active' check (status in ('active','closed')),
created_at timestamptz not null default now()
);
create table loan_terms (
id uuid primary key default gen_random_uuid(),
loan_id uuid not null references loans,
version int not null,
rate_bps int not null check (rate_bps >= 0),
rate_period text not null default 'month' check (rate_period in ('day','week','month','year')),
interest_type text not null default 'simple' check (interest_type in ('simple','compound')),
late_rate_bps int not null default 0 check (late_rate_bps >= 0),
grace_days int not null default 0 check (grace_days >= 0),
created_by uuid not null references profiles,
accepted_at timestamptz,
created_at timestamptz not null default now(),
unique (loan_id, version)
);
create table ledger_entries (
id uuid primary key default gen_random_uuid(),
loan_id uuid not null references loans,
kind text not null check (kind in ('loan_created','payment','interest_accrual','late_interest','terms_change','reversal')),
amount_paise bigint not null check (amount_paise >= 0),
entry_date date not null default current_date,
note text,
reverses_id uuid references ledger_entries,
created_by uuid not null references profiles,
created_at timestamptz not null default now(),
check ((kind = 'reversal') = (reverses_id is not null))
);
create unique index one_accrual_per_day on ledger_entries (loan_id, kind, entry_date)
where kind in ('interest_accrual','late_interest');
create function block_changes() returns trigger language plpgsql as $$
begin raise exception 'Records cannot be changed or deleted. Add a reversal entry instead.'; end $$;
create trigger ledger_append_only before update or delete on ledger_entries
for each row execute function block_changes();
create function log_loan_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
insert into ledger_entries (loan_id, kind, amount_paise, entry_date, created_by, note)
values (new.id, 'loan_created', new.principal_paise, new.start_date, new.created_by, 'Loan created');
return new;
end $$;
create trigger loan_created_log after insert on loans
for each row execute function log_loan_created();
create function log_terms_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
insert into ledger_entries (loan_id, kind, amount_paise, created_by, note)
values (new.loan_id, 'terms_change', 0, new.created_by,
'Terms v' || new.version || ': ' || (new.rate_bps / 100.0) || '% per ' || new.rate_period
|| ', ' || new.interest_type || ', late +' || (new.late_rate_bps / 100.0) || '%');
return new;
end $$;
create trigger terms_change_log after insert on loan_terms
for each row execute function log_terms_change();
create function kind_sign(k text) returns int language sql immutable as $$
select case k when 'loan_created' then 1 when 'interest_accrual' then 1
when 'late_interest' then 1 when 'payment' then -1 else 0 end $$;
create view loan_balances with (security_invoker = true) as
select e.loan_id,
sum(e.amount_paise * case when e.kind = 'reversal'
then -kind_sign(t.kind) else kind_sign(e.kind) end) as outstanding_paise
from ledger_entries e left join ledger_entries t on t.id = e.reverses_id
group by e.loan_id;
create table entry_confirmations (
entry_id uuid primary key references ledger_entries,
user_id uuid not null references profiles,
confirmed_at timestamptz not null default now()
);
create table device_tokens (
token text primary key,
user_id uuid not null references profiles on delete cascade,
platform text not null check (platform in ('android','ios')),
created_at timestamptz not null default now()
);
create table notifications (
id uuid primary key default gen_random_uuid(),
user_id uuid not null references profiles on delete cascade,
loan_id uuid references loans,
kind text not null check (kind in ('due_soon','due_today','overdue','ping')),
created_at timestamptz not null default now()
);
create function can_see_loan(l uuid) returns boolean language sql stable
security definer set search_path = public as $$
select exists (select 1 from loans where id = l
and auth.uid() in (created_by, lender_user_id, borrower_user_id)) $$;
create function can_write_loan(l uuid) returns boolean language sql stable
security definer set search_path = public as $$
select exists (select 1 from loans where id = l
and auth.uid() = coalesce(lender_user_id, created_by)) $$;
create function is_group_owner(g uuid) returns boolean language sql stable
security definer set search_path = public as $$
select exists (select 1 from groups where id = g and owner_id = auth.uid()) $$;
create function accept_terms(term_id uuid) returns void language sql
security definer set search_path = public as $$
update loan_terms set accepted_at = now()
where id = term_id and accepted_at is null
and exists (select 1 from loans l where l.id = loan_terms.loan_id
and l.borrower_user_id = auth.uid()) $$;
alter table profiles enable row level security;
alter table contacts enable row level security;
alter table groups enable row level security;
alter table group_members enable row level security;
alter table loans enable row level security;
alter table loan_terms enable row level security;
alter table ledger_entries enable row level security;
alter table entry_confirmations enable row level security;
alter table device_tokens enable row level security;
alter table notifications enable row level security;
create policy own_profile on profiles for all using (id = auth.uid()) with check (id = auth.uid());
create policy own_contacts on contacts for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy groups_read on groups for select using (owner_id = auth.uid()
or exists (select 1 from group_members m where m.group_id = groups.id and m.user_id = auth.uid()));
create policy groups_write on groups for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy members_read on group_members for select using (user_id = auth.uid() or is_group_owner(group_id));
create policy members_write on group_members for all using (is_group_owner(group_id)) with check (is_group_owner(group_id));
-- loans_read checks columns directly so a new loan can be read back right after insert.
create policy loans_read on loans for select using (auth.uid() in (created_by, lender_user_id, borrower_user_id));
create policy loans_insert on loans for insert with check (created_by = auth.uid() and is_group_owner(group_id));
create policy loans_update on loans for update using (can_write_loan(id));
create policy terms_read on loan_terms for select using (can_see_loan(loan_id));
create policy terms_insert on loan_terms for insert with check (can_write_loan(loan_id) and created_by = auth.uid());
-- Clients may add only payments and reversals. Interest entries come from the server job.
create policy ledger_read on ledger_entries for select using (can_see_loan(loan_id));
create policy ledger_insert on ledger_entries for insert with check (
can_write_loan(loan_id) and created_by = auth.uid() and kind in ('payment','reversal'));
create policy confirm_read on entry_confirmations for select using (
exists (select 1 from ledger_entries e where e.id = entry_id and can_see_loan(e.loan_id)));
create policy confirm_insert on entry_confirmations for insert with check (user_id = auth.uid()
and exists (select 1 from ledger_entries e where e.id = entry_id and can_see_loan(e.loan_id)));
create policy own_tokens on device_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_notifications on notifications for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Phase 2 additions (same as supabase/migrations/phase2_update.sql).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Phase 3 additions (same as supabase/migrations/phase3_update.sql).
-- ---------------------------------------------------------------------------
-- ₹ with Indian grouping, paise only when not zero: 5010 → ₹50.10, 123456700 → ₹12,34,567.
create or replace function fmt_rupees(p bigint) returns text
language plpgsql immutable set search_path = public as $$
declare
  whole text := (abs(p) / 100)::text;
  rest int := (abs(p) % 100)::int;
  head text;
  grouped text;
begin
  if length(whole) > 3 then
    head := left(whole, length(whole) - 3);
    grouped := right(whole, 3);
    while length(head) > 2 loop
      grouped := right(head, 2) || ',' || grouped;
      head := left(head, length(head) - 2);
    end loop;
    grouped := head || ',' || grouped;
  else
    grouped := whole;
  end if;
  return case when p < 0 then '-' else '' end || '₹' || grouped
    || case when rest <> 0 then '.' || lpad(rest::text, 2, '0') else '' end;
end $$;

-- Basis points as "10.00".
create or replace function fmt_pct(bps int) returns text
language sql immutable as $$ select to_char(bps / 100.0, 'FM999990.00') $$;

create or replace function period_days(p text) returns int
language sql immutable as $$
  select case p when 'day' then 1 when 'week' then 7 when 'month' then 30 when 'year' then 365 end $$;

-- amount × bps / 10000 / days, rounded half up to whole paise.
create or replace function daily_interest(amount bigint, bps int, days int) returns bigint
language sql immutable as $$
  select case when amount <= 0 or bps <= 0 then 0
    else round(amount::numeric * bps / (10000::numeric * days))::bigint end $$;

-- The engine. p_until is the last day to add (default: yesterday, India time).
-- Returns a small summary, e.g. {"until": "2026-11-03", "loans": 4, "entries_added": 4}.
create or replace function accrue_interest(p_until date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_until date := coalesce(p_until, (now() at time zone 'Asia/Kolkata')::date - 1);
  l record;
  t record;
  e record;
  d date;
  v_lender uuid;
  v_principal bigint;   -- principal left
  v_unpaid bigint;      -- interest added and not yet paid
  v_alloc jsonb;        -- payment id → [interest part, principal part]
  v_part bigint;
  v_days int;
  v_balance bigint;
  v_existing bigint;
  v_amount bigint;
  v_base bigint;
  v_loans int := 0;
  v_added int := 0;
  v_rows int;
begin
  for l in
    select * from loans where status = 'active' and start_date <= v_until order by created_at
  loop
    v_loans := v_loans + 1;
    v_lender := coalesce(l.lender_user_id, l.created_by);
    v_principal := 0;
    v_unpaid := 0;
    v_alloc := '{}'::jsonb;
    d := l.start_date;

    while d <= v_until loop
      -- 1. The day's own events, in the order they were recorded.
      for e in
        select le.id, le.kind, le.amount_paise, le.reverses_id, orig.kind as orig_kind
        from ledger_entries le
        left join ledger_entries orig on orig.id = le.reverses_id
        where le.loan_id = l.id and le.entry_date = d
          and le.kind in ('loan_created', 'payment', 'reversal')
        order by le.created_at, le.id
      loop
        if e.kind = 'loan_created' then
          v_principal := v_principal + e.amount_paise;
        elsif e.kind = 'payment' then
          v_part := least(e.amount_paise, greatest(v_unpaid, 0));   -- interest first
          v_unpaid := v_unpaid - v_part;
          v_principal := v_principal - (e.amount_paise - v_part);   -- then principal
          v_alloc := v_alloc || jsonb_build_object(e.id::text, jsonb_build_array(v_part, e.amount_paise - v_part));
        elsif e.kind = 'reversal' and e.orig_kind = 'payment' and v_alloc ? e.reverses_id::text then
          -- Undo the corrected payment exactly as it was applied.
          v_unpaid := v_unpaid + (v_alloc -> e.reverses_id::text ->> 0)::bigint;
          v_principal := v_principal + (v_alloc -> e.reverses_id::text ->> 1)::bigint;
        end if;
      end loop;

      -- 2. The terms in force that day.
      select * into t from loan_terms
      where loan_id = l.id
        and (version = 1 or (created_at at time zone 'Asia/Kolkata')::date <= d)
      order by version desc
      limit 1;

      if found then
        v_days := period_days(t.rate_period);
        v_balance := v_principal + v_unpaid;   -- start-of-interest balance for this day

        -- 3. Regular interest.
        v_existing := null;
        select amount_paise into v_existing from ledger_entries
        where loan_id = l.id and kind = 'interest_accrual' and entry_date = d;
        if v_existing is not null then
          v_unpaid := v_unpaid + v_existing;
        else
          v_base := case when t.interest_type = 'compound' then v_principal + v_unpaid else v_principal end;
          v_amount := daily_interest(v_base, t.rate_bps, v_days);
          if v_amount > 0 then
            insert into ledger_entries (loan_id, kind, amount_paise, entry_date, created_by, note)
            values (l.id, 'interest_accrual', v_amount, d, v_lender,
              initcap(t.interest_type) || ' interest ' || fmt_pct(t.rate_bps) || '% per ' || t.rate_period
              || ' on ' || fmt_rupees(v_base))
            on conflict (loan_id, kind, entry_date) where kind in ('interest_accrual', 'late_interest') do nothing;
            get diagnostics v_rows = row_count;
            v_added := v_added + v_rows;
            v_unpaid := v_unpaid + v_amount;
          end if;
        end if;

        -- 4. Late interest.
        v_existing := null;
        select amount_paise into v_existing from ledger_entries
        where loan_id = l.id and kind = 'late_interest' and entry_date = d;
        if v_existing is not null then
          v_unpaid := v_unpaid + v_existing;
        elsif l.next_due_date is not null
          and d > l.next_due_date + t.grace_days
          and t.late_rate_bps > 0
          and v_balance > 0 then
          v_amount := daily_interest(v_balance, t.late_rate_bps, v_days);
          if v_amount > 0 then
            insert into ledger_entries (loan_id, kind, amount_paise, entry_date, created_by, note)
            values (l.id, 'late_interest', v_amount, d, v_lender,
              'Late interest ' || fmt_pct(t.late_rate_bps) || '% per ' || t.rate_period
              || ' on ' || fmt_rupees(v_balance))
            on conflict (loan_id, kind, entry_date) where kind in ('interest_accrual', 'late_interest') do nothing;
            get diagnostics v_rows = row_count;
            v_added := v_added + v_rows;
            v_unpaid := v_unpaid + v_amount;
          end if;
        end if;
      end if;

      d := d + 1;
    end loop;
  end loop;

  return jsonb_build_object('until', v_until, 'loans', v_loans, 'entries_added', v_added);
end $$;

-- Only the server may run the engine (the Edge Function uses the service role).
revoke execute on function accrue_interest(date) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function accrue_interest(date) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke execute on function accrue_interest(date) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function accrue_interest(date) to service_role';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Phase 4 additions (same as supabase/migrations/phase4_update.sql).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Phase 5 additions (same as supabase/migrations/phase5_update.sql).
-- ---------------------------------------------------------------------------
-- 1. What each saved reminder needs so it can be shown in the receiver's language.
alter table notifications add column if not exists sent_on date not null
  default ((now() at time zone 'Asia/Kolkata')::date);       -- India-time day it was sent
alter table notifications add column if not exists to_lender boolean not null default false;
alter table notifications add column if not exists person_name text;    -- the other person on the loan
alter table notifications add column if not exists balance_paise bigint;
alter table notifications add column if not exists late_paise bigint;   -- late interest added so far
alter table notifications add column if not exists due_date date;

-- Never the same kind twice on one day for a loan (pings have their own limit).
create unique index if not exists one_reminder_per_day
  on notifications (loan_id, user_id, kind, sent_on) where kind <> 'ping';
create index if not exists notifications_by_user on notifications (user_id, created_at desc);

-- 2. Daily reminders. For every active loan with a due date and a balance:
--      2 days before the due date → 'due_soon'
--      on the due date            → 'due_today'
--      every day after it         → 'overdue'
--    The reminder goes to the borrower. If the borrower has no app (solo
--    lender loan) it goes to the lender instead.
--    Returns only the reminders created by this call, so a second run on the
--    same day sends nothing.
create or replace function queue_reminders(p_today date default null)
returns table (notification_id uuid, user_id uuid, language text, kind text, loan_id uuid,
               to_lender boolean, person_name text, balance_paise bigint, late_paise bigint, due_date date)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Kolkata')::date);
  r record;
  v_id uuid;
begin
  for r in
    select l.id as loan_id, l.next_due_date,
      coalesce(l.borrower_user_id, l.lender_user_id, l.created_by) as receiver,
      (l.borrower_user_id is null) as to_lender,
      case
        when l.borrower_user_id is null then c.name                 -- lender is told about the contact
        when l.lender_user_id is not null then lp.name              -- borrower is told about the lender
        else c.name                                                 -- solo borrower: the contact is the lender
      end as person_name,
      b.outstanding_paise::bigint as balance,
      coalesce((select sum(e.amount_paise) from ledger_entries e
                where e.loan_id = l.id and e.kind = 'late_interest'), 0)::bigint as late,
      case
        when l.next_due_date - v_today = 2 then 'due_soon'
        when l.next_due_date = v_today then 'due_today'
        when l.next_due_date < v_today then 'overdue'
      end as kind
    from loans l
    join loan_balances b on b.loan_id = l.id
    left join contacts c on c.id = l.contact_id
    left join profiles lp on lp.id = l.lender_user_id
    where l.status = 'active' and l.next_due_date is not null
      and b.outstanding_paise > 0
      and l.next_due_date - v_today <= 2
  loop
    continue when r.kind is null;
    v_id := null;
    insert into notifications (user_id, loan_id, kind, sent_on, to_lender, person_name,
                               balance_paise, late_paise, due_date)
    values (r.receiver, r.loan_id, r.kind, v_today, r.to_lender, coalesce(r.person_name, ''),
            r.balance, r.late, r.next_due_date)
    on conflict (loan_id, user_id, kind, sent_on) where kind <> 'ping' do nothing
    returning id into v_id;
    if v_id is not null then
      return query
        select v_id, r.receiver, p.language, r.kind::text, r.loan_id, r.to_lender,
               coalesce(r.person_name, ''), r.balance, r.late, r.next_due_date
        from profiles p where p.id = r.receiver;
    end if;
  end loop;
end $$;

-- 3. Manual ping from the lender of a shared loan: at most 3 per loan per day.
create or replace function send_ping(p_loan_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  l loans%rowtype;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_id uuid;
begin
  select * into l from loans
  where id = p_loan_id and status = 'active'
    and lender_user_id = auth.uid()
    and borrower_user_id is not null and borrower_user_id <> auth.uid()
  for update;                       -- two taps at once still count one after the other
  if not found then
    raise exception 'PING_NOT_ALLOWED';
  end if;
  if (select count(*) from notifications
      where loan_id = l.id and kind = 'ping' and sent_on = v_today) >= 3 then
    raise exception 'PING_LIMIT';
  end if;

  insert into notifications (user_id, loan_id, kind, sent_on, to_lender, person_name,
                             balance_paise, late_paise, due_date)
  values (l.borrower_user_id, l.id, 'ping', v_today, false,
          coalesce((select name from profiles where id = l.lender_user_id), ''),
          coalesce((select outstanding_paise from loan_balances where loan_id = l.id), 0),
          coalesce((select sum(amount_paise) from ledger_entries
                    where loan_id = l.id and kind = 'late_interest'), 0),
          l.next_due_date)
  returning id into v_id;
  return v_id;
end $$;

-- 4. Save this phone's push token for the signed-in person. If the phone was
--    used by another account before, the token moves to the new account.
create or replace function register_device_token(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or coalesce(p_token, '') = '' then
    raise exception 'Not signed in';
  end if;
  insert into device_tokens (token, user_id, platform)
  values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform;
end $$;

-- 5. Only the server runs the daily reminders.
revoke execute on function queue_reminders(date) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function queue_reminders(date) from anon';
    execute 'revoke execute on function send_ping(uuid) from anon';
    execute 'revoke execute on function register_device_token(text, text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke execute on function queue_reminders(date) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function queue_reminders(date) to service_role';
  end if;
end $$;

-- 6. Realtime: the Reminders screen updates when a reminder arrives.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table notifications;
    exception when duplicate_object then null;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Phase 6 additions (same as supabase/migrations/phase6_update.sql).
-- ---------------------------------------------------------------------------
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
