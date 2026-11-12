// Checks the push message text (run with: node --experimental-strip-types messages_test.mjs)
import { buildMessage, formatRupees, formatDate } from '../functions/send-reminders/messages.ts';
let fail = 0;
const eq = (label, got, want) => { const ok = got === want; if (!ok) fail++; console.log(ok ? 'PASS' : 'FAIL', label, ok ? '' : `→ got "${got}", want "${want}"`); };
eq('rupees 500', formatRupees(50000), '₹500');
eq('rupees with paise', formatRupees(53746), '₹537.46');
eq('Indian grouping', formatRupees(123456700), '₹12,34,567');
eq('date', formatDate('2026-11-04', 'en'), '04 Nov 2026');
const base = { language: 'en', to_lender: false, person_name: 'Bala', balance_paise: 53746, late_paise: 72, due_date: '2026-10-20' };
eq('overdue names the late interest', buildMessage({ ...base, kind: 'overdue' }).body,
  'Your payment to Bala is overdue. Late interest added so far: ₹0.72. Balance: ₹537.46.');
eq('due soon to a solo lender', buildMessage({ ...base, kind: 'due_soon', to_lender: true, person_name: 'Ramu' }).body,
  "Ramu's payment is due on 20 Oct 2026. Balance: ₹537.46.");
eq('ping title', buildMessage({ ...base, kind: 'ping' }).title, 'Reminder from Bala');
for (const language of ['en', 'te', 'hi', 'xx']) for (const kind of ['due_soon', 'due_today', 'overdue', 'ping']) for (const to_lender of [false, true]) {
  const m = buildMessage({ ...base, language, kind, to_lender });
  if (!m.title || !m.body.includes('₹537.46') || m.body.includes('undefined')) { fail++; console.log('FAIL', language, kind, to_lender, m); }
}
console.log('all 32 language/kind/receiver combinations produce a message');
console.log(fail ? `\n${fail} failed` : '\nall passed'); if (fail) process.exit(1);
