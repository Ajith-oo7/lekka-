# Lekka — Phases 4 to 6 status, and what Phase 7 needs (10 Nov 2026)

## Phase 4: shared loans — built
- Invite by 10-character code (single use, 7 days); the invite message also carries a lekka://join/CODE link.
- Join with code (Home → Money Borrowed): borrower becomes the borrower on that person's loans in the group, joins the group, and the lender's contact is linked to their account.
- Borrower sees the loan and Records, must tap Accept terms; later changes are logged only. Borrower cannot change terms, record payments or close the loan.
- Borrower confirms payments; lender sees "Confirmed by borrower".
- Solo borrower mode: New Loan → "I took this loan".
- Close loan. Live updates between phones (Supabase Realtime).
- Database: supabase/migrations/phase4_update.sql.

## Phase 5: reminders — built
- queue_reminders(): due_soon (2 days before), due_today, overdue (daily); to the borrower, or to the lender when the borrower has no app; never the same kind twice a day.
- send_ping(): lender of a shared loan only, 3 per loan per day.
- Edge Function send-reminders (daily run + pings), push text in en/te/hi; FCM via a service-account secret. Scheduled 09:00 IST in supabase/cron.sql.
- App: push registration (works without Firebase set up, just no push), Send ping button, Reminders screen.
- Database: supabase/migrations/phase5_update.sql.

## Phase 6: polish — buildable parts done
- Settings → Report a problem (feedback table; owner reads in the dashboard).
- Large phone font sizes capped at 1.4×.
- docs/TESTING.md, docs/RELEASE.md, docs/translation_review.csv (238 strings).
- Still to do by the owner: native-speaker review, device checks, test builds, backups, weeks of real use.

## Verified
- Database tests on the final schema.sql: interest 13/13, shared loans 33/33, reminders 20/20, problem reports 4/4, Phase 2 privacy checks, push message text in all 32 language/kind/receiver combinations.

## Not verified
- The Flutter app has never been compiled or run (no Flutter SDK in the build workspace). Expect some compile fixes on first `flutter analyze`.
- Edge Functions are not deployed; push delivery, Realtime and the invite link are untested on devices.
- firebase_core / firebase_messaging version numbers in pubspec.yaml may need adjusting.

## Findings and decisions for the owner
- Supabase free plan has no automatic backups: move to Pro or export weekly before real loans go in.
- Reminders run at 09:00 IST (the spec gave no time).
- Due dates do not roll forward: an overdue loan gets late interest and a daily reminder until paid or closed.
- Records labels are the same for both sides ("Loan given", "Payment received").

## Phase 7 — not built
See docs/LAUNCH_CHECKLIST.md.
