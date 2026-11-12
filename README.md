# Lekka — Phases 1 to 6

- **Phase 1, app skeleton and sign-in:** sign up and sign in, English / Telugu / Hindi, light and dark mode.
- **Phase 2, solo lender core:** groups, borrowers (contacts) who have no app, new loan with terms,
  loan detail, record a payment, Records with corrections, and Home / Summary on real data.

- **Phase 3, interest engine:** a daily server job adds interest and late interest to Records
  from the saved terms; Change terms creates a new version; interest notes in all three languages.

- **Phase 4, shared loans:** invite by code, borrower joins and sees the loan and Records, accept
  terms, confirm payments, solo borrower mode, close loan, live updates between phones.
- **Phase 5, reminders:** daily push reminders (2 days before, on the due date, every day while
  overdue), manual pings (3 a day per loan), Reminders screen, in the receiver's language.
- **Phase 6, polish:** Report a problem, large-text cap, translation review sheet, test checklist,
  release guide.

Phase 7 (public launch) is not built: see `docs/LAUNCH_CHECKLIST.md` for what it needs.

**Current state:** the database rules are tested (`supabase/tests`), but the Flutter app has not been
compiled or run yet. Expect some fixes on the first `flutter analyze`. See `docs/status/`.

**New here?** Read `ABOUT_LEKKA.txt`: the whole app in plain words (use case, a worked story,
functions, how to use it, the calculations).

**Guides:** `docs/RELEASE.md` (setup for Phases 4 to 6, push, backups, test builds),
`docs/TESTING.md` (what to check on a phone), `docs/translation_review.csv` (for native speakers), `docs/spec/` (the original build prompt and phases).

## 1. Database (Supabase)

1. Create a free project at supabase.com.
2. **Fresh project:** open SQL Editor, paste all of `supabase/schema.sql`, run it.
   **Already ran an earlier schema?** Run the migrations instead, in order:
   - `supabase/migrations/phase1_update.sql`: saves the sign-up language and applies the loans policy fix
   - `supabase/migrations/phase2_update.sql`: `create_loan` (loan + terms in one step), one correction per
     record, a clear error when anything tries to edit or delete Records, and a tidier terms note.
   - `supabase/migrations/phase3_update.sql`: the interest engine, `accrue_interest()`.
   - `phase4_update.sql`: invites, shared loans, solo borrower mode, tighter rules on loans.
   - `phase5_update.sql`: reminders and pings.
   - `phase6_update.sql`: problem reports.

   All are safe to run twice.
3. Authentication → Sign In / Providers → Email: keep it enabled.
   For quick testing with your circle you can turn **Confirm email** off.
   If you leave it on, the app tells people to confirm and then sign in.
4. Project Settings → API: copy the **Project URL** and the **anon public** key.
   Never the `service_role` / secret key. The app refuses to start if you give it one.

## 2. App

You need Flutter 3.32 or newer (`flutter --version`) and Android Studio.
A Mac with Xcode for iPhone.

```bash
# from the repository root

# Creates the android/ and ios/ folders. Existing files in lib/ are kept.
flutter create . --project-name lekka --org com.lekka --platforms android,ios

cp env.example.json env.json      # then put your URL and anon key in env.json
flutter pub get                   # also generates lib/l10n/app_localizations.dart
dart format .
flutter analyze
flutter test

# Plug in a phone (USB debugging on) or start an emulator:
flutter run --dart-define-from-file=env.json
```

For a release build on Android, add this line to
`android/app/src/main/AndroidManifest.xml`, above `<application`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

(Debug builds already have it.)

## 3. Phase 1 checks ("done when")

| Check | How |
|---|---|
| Create an account, sign out, sign back in | Sign up with name, email, password → home screen. Settings (gear) → Sign out → Sign in again. |
| Switching to Telugu or Hindi changes every label, no clipped text | Tap తెలుగు / हिन्दी on the sign-in screen, and in Settings. Visit all 4 tabs, Chits and Settings. Also try with the phone's font size at its largest. |
| Looks right in light and dark mode | Settings → Theme → Light / Dark / Same as phone. |
| New user gets a profile row | SQL Editor: `select id, name, language, created_at from profiles order by created_at desc;` The new person's name and chosen language should be there. |

Also worth checking: a wrong password shows "Email or password is wrong"
under the password field; an already-used email shows its error under the
email field.

## 4. Phase 2 checks ("done when")

| Check | How |
|---|---|
| Bala creates a group, adds Vasu, creates a ₹500 loan at 10% | Home → Groups → New group "Family" → New Loan → Borrower → Add a new person "Vasu" (no phone) → ₹500, 10, Month, Simple → Save loan. |
| Records shows "Loan given" and "Terms updated" | On the loan page, under Records. |
| A ₹100 payment lowers the balance to ₹400 | Record payment → 100 → Save payment. |
| Correcting it brings it back to ₹500; both entries stay | Press and hold the payment → Add correction. The payment gets a line through it; a "Correction" row appears. |
| A second account can't see Bala's loans | Sign out, sign up as someone else: Home, Records, Groups and Summary are all empty. |

These rules were checked against the real schema (row-level security on) before delivery:
₹500 → ₹400 → ₹500, both entries kept; a second correction of the same payment is refused;
editing or deleting a record fails with "Records cannot be changed or deleted"; a second account
sees 0 loans, records, groups and contacts and cannot add to Bala's group or loans.

## 5. Phase 3: daily interest job

The maths is in the database function `accrue_interest()` (phase3_update.sql). The Edge Function
`accrue-interest` runs it, and pg_cron calls the Edge Function every day at 00:30 India time.

One-time setup (needs the Supabase CLI: https://supabase.com/docs/guides/cli):

```bash
supabase login
supabase link --project-ref YOUR-PROJECT-REF
openssl rand -hex 32                     # makes a long random secret: copy it, you need it twice
supabase secrets set CRON_SECRET=PASTE-THE-SECRET-HERE
supabase functions deploy accrue-interest --no-verify-jwt
```

Then open `supabase/cron.sql`, put in your project ref and the same CRON_SECRET, and run it in the SQL editor.
(Dashboard → Integrations: make sure **Cron** and **Vault** are enabled.)

`--no-verify-jwt` is on purpose: the function checks the `x-cron-secret` header itself and refuses
anything else. The service-role key stays inside Supabase and is never in the app.

### Phase 3 checks ("done when")

The whole engine is already tested in Postgres: run `cd supabase/tests && npm install && npm test`.
All 13 checks pass, including every case below.

| Check | Result in the test |
|---|---|
| ₹500 at 10% a month, simple, 30 days, no payments: within ₹0.50 of ₹550 | ₹550.10 |
| Same loan, compound: slightly higher | ₹552.50 |
| A payment goes to interest first, then principal | ₹100 after 10 days: ₹16.70 to interest, ₹83.30 to principal; next day's interest is on ₹416.70 |
| Past due date + grace days: one late-interest entry per day | due 5 Oct, 3 grace days → entries from 9 Oct, one per day |
| Changing the rate creates version 2; earlier days keep the old rate | 15 days at 10%, then 20% from the day v2 was saved; v1 unchanged |
| Running the job twice on the same day adds nothing | second run: 0 entries added |

To see it on a phone: create a loan with a **start date 30 days ago**, then in the SQL editor run
`select accrue_interest();` The loan's Records fill with 30 "Interest added" entries and the balance
shows about ₹550.10. Running it again adds nothing.

### Rules the engine follows (please confirm)

- 30-day months (week 7, year 365). Payments pay interest first. Late interest is daily, on the balance.
- Interest for a day is added after that day ends; the start date counts as day 1.
- New terms count from the day they are saved (India time). Days already passed keep the old terms.
- Late interest is on the balance at the start of that day's interest (after that day's payments).
- A correction undoes its payment from the correction's date; interest already added stays in Records.
- Rounding to whole paise each day can drift by up to 1 paisa a day (₹550.10 instead of ₹550.00 above).
- The due date does not move by itself yet, so a loan past its due date keeps getting late interest
  until it's paid or closed.

## Where things are

```
lib/
  main.dart                 start-up, Supabase connection, config check
  app.dart                  theme, router (sign-in redirect), localization
  core/                     theme.dart, money.dart, dates.dart, widgets.dart, routes.dart, config.dart
  data/                     auth_repo.dart, profile.dart, providers.dart (language, theme, auth)
                            repo.dart, models.dart, loan_providers.dart (Phase 2 data)
  features/
    auth/                   sign up / sign in
    home/                   app bar, bottom bar shell, Loans tab, summary card
    groups/                 groups list, group page, new group dialog
    loans/                  new loan, loan detail, record payment, borrower picker, loan row card
    records/                Records list with corrections (all loans)
    summary/                totals and loans by status
    invite/                 Join with code
    reminders/              reminders received
    chits/                  "Coming soon"
    settings/               language, theme, sign out
  l10n/                     app_en.arb, app_te.arb, app_hi.arb, TRANSLATION_REVIEW.md
supabase/
  schema.sql                full schema (section 7 of the build prompt)
  migrations/               phase1 … phase6 updates
  functions/accrue-interest/   daily interest job (Edge Function)
  functions/send-reminders/    daily reminders and pings (Edge Function)
  cron.sql                  schedules interest at 00:30 IST and reminders at 09:00 IST
  tests/                    database tests (npm test)
```

## Notes

- The "monthly interest" on the summary card is an estimate (balance × rate for 30 days).
  The real amounts are the daily entries in Records.
- "Due soon" = due today or within 2 days; "Overdue" = past the due date.
- A payment can't be more than the balance, or dated before the loan started or in the future.
- Fonts load from Google Fonts on first launch (needs internet once). Bundling
  them in the app is a Phase 6 polish item.
