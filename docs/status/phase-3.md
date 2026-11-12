# Lekka — Phase 3 status (4 Nov 2026)

## Built
- accrue_interest(p_until) database function (supabase/migrations/phase3_update.sql): replays each active loan day by day, uses stored entries where they exist, adds missing interest and late-interest entries. Notes like "Simple interest 10.00% per month on ₹500". Only service_role may execute it.
- Edge Function supabase/functions/accrue-interest: checks x-cron-secret, calls the function with the service-role key (server only), logs counts only.
- supabase/cron.sql: pg_cron job at 19:00 UTC (00:30 IST) via pg_net, secret kept in Vault.
- App: Change terms screen (new version), interest notes translated in Records.

## Verified (13/13 engine tests)
- ₹500 @10%/month simple, 30 days → ₹550.10 (within ₹0.50 of ₹550). Compound → ₹552.50.
- Payment to interest first, then principal.
- Late interest from due + grace, one per day; no duplicates.
- Terms v2: earlier days keep v1; v1 row unchanged.
- Second run same day adds 0; catch-up equals daily runs; a correction undoes its payment from that date; a paid-off loan gets no interest; app users cannot run the engine.

## Rules to confirm with the owner
- 30-day months, interest first, late interest daily on balance.
- A day's interest is added after it ends; start date is day 1.
- New terms apply from the India-time day they are saved.
- Late interest base = balance before that day's interest.
- Due date does not move automatically, so late interest continues until paid or closed.
