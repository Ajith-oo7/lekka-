-- Schedules the daily interest job at 00:30 India time (19:00 UTC the day before).
-- Run once in the Supabase SQL editor AFTER deploying the accrue-interest Edge Function.
--
-- Replace the two placeholders first:
--   YOUR-PROJECT-REF  - from your project URL, https://YOUR-PROJECT-REF.supabase.co
--   YOUR-CRON-SECRET  - the same long random text you set with:
--                       supabase secrets set CRON_SECRET=YOUR-CRON-SECRET

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Keep the secret in Supabase Vault, not in the job text.
-- (If you run this file again, skip this line: the secret already exists.)
select vault.create_secret('YOUR-CRON-SECRET', 'lekka_cron_secret');

-- Scheduling under the same name again replaces the job instead of adding a second one.
select cron.schedule(
  'lekka-accrue-interest',
  '0 19 * * *',  -- 19:00 UTC = 00:30 IST
  $cmd$
    select net.http_post(
      url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/accrue-interest',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'lekka_cron_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    );
  $cmd$
);

-- Check it:   select jobname, schedule, active from cron.job;
-- Last runs:  select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;
-- Function result: Supabase dashboard → Edge Functions → accrue-interest → Logs.

-- ---------------------------------------------------------------------------
-- Phase 5: daily reminders at 09:00 India time (03:30 UTC), after the interest
-- job has run. Deploy the send-reminders Edge Function first, and replace
-- YOUR-PROJECT-REF below. It uses the same secret as above.
-- ---------------------------------------------------------------------------
select cron.schedule(
  'lekka-send-reminders',
  '30 3 * * *',  -- 03:30 UTC = 09:00 IST
  $cmd$
    select net.http_post(
      url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/send-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'lekka_cron_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    );
  $cmd$
);
