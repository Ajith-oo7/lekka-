# Lekka — test checklist (Phases 4 to 6)

Do every item on a real phone. Write down anything that fails, with the screen
and the language, and fix it before moving on. Testers can also use
Settings → Report a problem.

## Phase 4: shared loans (two phones)

| # | Check | How |
|---|---|---|
| 1 | Two phones see the same balance | Bala: open a loan → "Invite Vasu to this loan" → copy the code. Vasu (own account): Home → Money Borrowed → Join with code. Both now show the same loan and balance. |
| 2 | Vasu can only accept terms | On Vasu's phone the loan shows "Accept the terms" and no Change terms, Record payment or Close loan. Tap Accept. Bala's phone shows "Vasu accepted the terms". |
| 3 | Later changes are logged | Bala: Change terms. Vasu sees "Terms updated" in Records without being asked to accept again. |
| 4 | Vasu confirms a payment | Bala: Record payment. Vasu: Records → Confirm payment. Bala sees "Confirmed by borrower". |
| 5 | A third account sees nothing | Sign in as someone else: no loans, records or groups. The used code is refused. |
| 6 | Solo borrower | Vasu: Money Borrowed → New Loan → "I took this loan" → add the lender as a new person. The loan shows under Money Borrowed as "you owe"; Bala cannot see it. |
| 7 | Live update | With both phones open on the loan, Bala records a payment: Vasu's balance changes within a few seconds without pulling to refresh. |

## Phase 5: reminders

| # | Check | How |
|---|---|---|
| 1 | All three reminders on the right days | Make a shared test loan due in 2 days. At 09:00 India time Vasu gets "Payment due in 2 days"; on the due date "Payment due today"; each day after "Payment overdue" with the late interest added. To test without waiting, run `select * from queue_reminders('YYYY-MM-DD');` in the SQL editor with the date you want to pretend it is: the reminders appear on the Reminders screen (no push from the SQL editor). |
| 2 | A ping arrives within seconds | Bala: open the shared loan → Send ping. Vasu's phone shows the notification. A 4th ping the same day is refused. |
| 3 | Solo-lender loans remind only the lender | A loan whose borrower has no app: Bala gets the reminders. |
| 4 | Receiver's language | Vasu's app in Telugu: the push and the Reminders screen are in Telugu. |
| 5 | Sign out stops push | Vasu signs out: no more notifications on that phone. |

## Phase 6: polish

Screens to visit for each check: sign-in, Home (both sides), loan detail, New
Loan, Change terms, Record payment, Records, Reminders, Summary, Groups, Join
with code, Chits, Settings.

- [ ] **Telugu and Hindi:** every label changes, nothing is cut off, nothing is still in English.
- [ ] **Small screen:** a small Android phone (about 5 inches). No overflow stripes, every button reachable.
- [ ] **Large text:** phone font size at its largest. Text wraps; amounts stay readable.
- [ ] **Dark mode:** every screen, including dialogs and the amber "Accept the terms" card.
- [ ] **Slow network:** switch to 2G / poor signal. Screens show a spinner, then load. Buttons cannot be tapped twice while saving.
- [ ] **No network:** aeroplane mode. Lists show "Couldn't load. Check your internet." with Try again; forms show an error and keep what was typed.
- [ ] **Empty states:** a brand-new account shows friendly empty screens on all four tabs.
- [ ] **Amounts:** ₹12,34,567 grouping; ₹500.50 shows paise; a payment larger than the balance is refused.
- [ ] **Records can't be changed:** there is no way in the app to edit or delete an entry, only to correct a payment.
- [ ] **Daily jobs:** in the Supabase dashboard (Integrations → Cron), both jobs show a successful run each day.
- [ ] **Backup:** a database export exists from this week (see RELEASE.md).

## Database tests

`cd supabase/tests && npm install && npm test` runs all the database rules
(records, privacy between accounts, interest, shared loans, reminders, problem
reports) against `supabase/schema.sql` in a throwaway database.
