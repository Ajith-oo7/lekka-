-- Phase 5 update: reminders. Run once in the Supabase SQL editor after
-- phase4_update.sql. Safe to run more than once.
--
-- The daily job (pg_cron → Edge Function send-reminders → queue_reminders)
-- decides who gets which reminder, saves it in the notifications table (the
-- Reminders screen reads that) and the Edge Function sends the push message.

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
