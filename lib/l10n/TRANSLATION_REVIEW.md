# Translation review needed

Every Telugu and Hindi string (`app_te.arb`, `app_hi.arb`, and the push
messages in `supabase/functions/send-reminders/messages.ts`) was drafted
without a native speaker and must be reviewed before closed-circle testing.

Use `docs/translation_review.csv`: it lists every string with where it
appears, and has columns for "OK?" and "better wording".

Words worth a second look: Loans / Chits (అప్పులు / చిట్టీలు, कर्ज़ / चिट फंड),
late interest (ఆలస్య వడ్డీ, लेट ब्याज), grace days (గడువు రోజులు, छूट के दिन),
the status words, "Accept terms", and the tagline (a placeholder in English too).

The app name "Lekka" and the language names are the same in every file on purpose.
