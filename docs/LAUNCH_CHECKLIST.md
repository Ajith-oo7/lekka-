# Lekka — Phase 7: public launch checklist

Phase 7 starts only after the closed circle has used Lekka for a few weeks
with real loans and the feedback is good. None of it is built yet, because
each item needs a decision, an account or a document that only the app owner
can provide.

| Item | What is needed first | Then |
|---|---|---|
| Phone-number OTP login | An SMS provider that delivers in India, and DLT registration of the sender ID and message template (this takes days to weeks). A decision on whether email login stays as well. | Turn on phone sign-in in Supabase Auth and add a phone/OTP form beside the email form. Existing email accounts need a way to add their phone. |
| Independent security review | Someone outside the project to review the database rules (`supabase/schema.sql`), the two Edge Functions and the app. | Fix what they find. The database tests in `supabase/tests` are a starting point for them. |
| Privacy policy and terms of use | The owner's legal advice: what is collected (name, email, contacts' names and phones, loan records, push tokens), where it is stored (Supabase region), how deletion works. | Add both as pages linked from sign-up and Settings, and add account deletion (both app stores require it). |
| Legal and licensing | Confirmation by the owner that opening a moneylending record tool to the public is allowed where it will be offered. | The app text keeps making no compliance claims. |
| Store listings | Play Console and App Store Connect accounts, app icon, screenshots in three languages, description, data-safety answers. | Production releases after the review above. |
| The real Chits feature | A specification: who runs a chit, members, monthly amount, auction or fixed order, commission, what each member sees. Nothing about this is defined in the build prompt. | Design, then build in its own phases like loans were. |
| Support and monitoring | Who answers problem reports and how fast; an alert when a daily job fails. | A support contact in the app; a daily check on the two cron jobs. |

Decisions still open from earlier phases:

- Should a loan's due date move forward by itself each period? Today it stays fixed, so a loan past its due date gets late interest (and a daily overdue reminder) until it is paid or closed.
- Reminders go out at 09:00 India time. Change the schedule in `supabase/cron.sql` if another time suits better.
- Records labels are the same for both sides ("Loan given", "Payment received"). A borrower may find "Loan taken" and "Payment made" clearer.
