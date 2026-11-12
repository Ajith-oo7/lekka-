# Lekka — Phase 1 status (4 Nov 2026)

## Built
- Flutter project (Riverpod, go_router, supabase_flutter, google_fonts, shared_preferences), Supabase URL and anon key passed via --dart-define-from-file=env.json; app refuses to start with a service-role/secret key.
- Email + password sign-up (with name) and sign-in; errors shown under the email/password field; handles Supabase "confirm email" mode.
- English, Telugu, Hindi from ARB files. Picked on the sign-in screen, saved on the device and on profiles.language, changeable in Settings.
- Theme: emerald/slate palette in light and dark; Plus Jakarta Sans + Inter with Noto Sans Telugu / Devanagari fallback.
- Home shell: app bar (logo tile, Lekka, tagline, Loans/Chits pill, settings), user card with Money Lent/Borrowed switch, summary card, bottom bar Loans/Records/Reminders/Summary.
- Chits "Coming soon" placeholder. Settings: language, theme (system/light/dark), sign out.

## Schema change
- handle_new_user also stores the sign-up language from user metadata. supabase/migrations/phase1_update.sql applies this plus the loans_read policy fix to an existing database.

## Small decisions to confirm
- Theme choice is saved in shared_preferences too (the prompt lists it for language only).
- Tagline "Every loan, clearly recorded" is a placeholder.
