-- Phase 3 update: the interest engine. Run once in the Supabase SQL editor
-- after phase2_update.sql. Safe to run more than once.
--
-- The daily job (pg_cron → Edge Function accrue-interest → this function) adds
-- interest and late interest entries to Records from the saved terms.
--
-- Rules (build prompt, section 8):
--   * Period days: day = 1, week = 7, month = 30, year = 365.
--   * Daily rate = rate_bps / 10000 / period_days, from the terms version in force that day.
--     Version 1 applies from the loan's start date. A later version applies from the
--     India-time day it was saved (that day included). Earlier days keep the old terms.
--   * Payments go to unpaid interest first, then to principal.
--   * Simple:   interest(day) = principal left × daily rate
--   * Compound: interest(day) = (principal left + unpaid interest) × daily rate
--   * Late interest: on each day after next_due_date + grace_days, while the balance is
--     above zero: balance × late_rate_bps / 10000 / period_days. "Balance" is the
--     balance at the start of that day's interest (after that day's payments).
--   * Every amount is rounded half up to whole paise. Zero amounts are skipped.
--   * Interest for a day is added after the day ends. The job at 00:30 India time adds
--     the day that just finished, and any earlier days it missed (catch-up).
--   * One entry per loan, per kind, per day (unique index one_accrual_per_day), so
--     running the job twice adds nothing the second time.
--
-- Known limit: rounding each day to whole paise can drift by up to 1 paisa a day
-- from the exact figure (for ₹500 at 10% a month: 166.67 paise/day → 167, so 30
-- days give ₹550.10 instead of ₹550.00).
--
-- Replaying a loan: the function walks every day from the start date. On days that
-- already have entries it uses the stored amounts (Records are never rewritten), and
-- it only calculates days that are missing. A correction (reversal) undoes its
-- payment from the reversal's date onward; interest already added stays.

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
