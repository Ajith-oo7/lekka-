# Lekka — Phase 2 status (4 Nov 2026)

## Built
- Groups: list, New group, group page listing its loans with a New loan button.
- Borrowers: pick a contact or add a new person (name, optional phone) inside New loan.
- New loan: group, borrower, amount, interest % and period (day/week/month/year), simple or compound, late interest % and grace days, start date, next due date. Saved through a create_loan database function so the loan and terms v1 are created together.
- Loan detail: outstanding balance, status, amount given, dates, current terms, Record payment.
- Record payment: amount (not more than the balance), date (not before start or in the future), optional note.
- Records: per loan and across all loans, newest first, translated labels; long-press a payment to add a correction; the original stays with a line through it.
- Home and Summary on real data; New Loan button on the Loans tab.

## Database changes (supabase/migrations/phase2_update.sql)
- create_loan(...) function (security invoker, so RLS still applies).
- Unique index: a record can be corrected only once.
- Update/delete policies on ledger_entries so edits from the app reach the append-only trigger and fail with "Records cannot be changed or deleted" (before, they silently did nothing).
- Terms note formatted as 10.00%.

## Verified
- In Postgres (PGlite) with RLS: ₹500 loan → Loan given + Terms updated; ₹100 payment → ₹400; correction → ₹500 with both entries kept; second correction refused; edit/delete refused; a second account sees nothing and cannot write to Bala's group or loan.

## Decisions to confirm
- Due soon = due today or within 2 days; overdue = past the due date.
- Monthly interest on the summary card is an estimate.
