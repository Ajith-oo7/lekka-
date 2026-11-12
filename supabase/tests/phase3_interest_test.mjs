import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
const db = new PGlite();
const read = (p) => fs.readFileSync(p, 'utf8');
const q = async (sql, p) => (await db.query(sql, p)).rows;
const B = '11111111-1111-1111-1111-111111111111';
let pass = 0, fail = 0;
const check = (label, ok, info = '') => { ok ? pass++ : fail++; console.log(ok ? 'PASS' : 'FAIL', label, info); };

await db.exec(`create schema auth;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create role authenticated; create role anon; create role service_role;`);
await db.exec(read(new URL('../schema.sql', import.meta.url)).replace(/create extension if not exists pgcrypto;/, ''));
// schema.sql already includes Phase 3.
await db.exec(`grant usage on schema public, auth to authenticated; grant all on all tables in schema public to authenticated;`);
await db.exec(`insert into auth.users values ('${B}', '{"name":"Bala"}');`);
const [g] = await q(`insert into groups (owner_id, name) values ($1,'Family') returning id`, [B]);
const [c] = await q(`insert into contacts (owner_id, name) values ($1,'Vasu') returning id`, [B]);
await db.exec(`select set_config('request.jwt.claim.sub','${B}',false)`);

const mk = async ({ start = '2026-10-01', due = '2026-12-31', type = 'simple', rate = 1000, late = 0, grace = 0, amt = 50000 } = {}) =>
  (await q(`select create_loan($1,$2,$3,$4::date,$5::date,$6,'month',$7,$8,$9) id`, [g.id, c.id, amt, start, due, rate, type, late, grace]))[0].id;
const bal = async (id) => Number((await q('select outstanding_paise b from loan_balances where loan_id=$1', [id]))[0].b);
const run = async (until) => (await q(`select accrue_interest($1::date) r`, [until]))[0].r;
const entries = async (id, kind) => q(`select entry_date::text d, amount_paise::int a, note from ledger_entries where loan_id=$1 and kind=$2 order by entry_date`, [id, kind]);

// Each scenario is run on its own fresh set of loans: close earlier ones so they don't count.
const closeAll = () => db.exec(`update loans set status='closed'`);

// 1. Simple, 30 days, no payments
const simple = await mk();
await run('2026-10-30');
const s = await bal(simple);
check('Simple ₹500 @10%/month, 30 days ends within ₹0.50 of ₹550', Math.abs(s - 55000) <= 50, `→ ${s / 100}`);
check('One interest entry per day (30)', (await entries(simple, 'interest_accrual')).length === 30);
console.log('   sample note:', (await entries(simple, 'interest_accrual'))[0].note);

// 2. Compound gives slightly higher
await closeAll();
const comp = await mk({ type: 'compound' });
await run('2026-10-30');
const cb = await bal(comp);
check('Compound is slightly higher than simple', cb > s && cb - s < 500, `→ ${cb / 100} vs ${s / 100}`);

// 3. Idempotent
const again = await run('2026-10-30');
check('Running the job twice on the same day adds nothing', again.entries_added === 0, JSON.stringify(again));

// 4. Interest first, then principal
await closeAll();
const pay = await mk();
await run('2026-10-10'); // 10 days × 167 = 1670 unpaid interest
await q(`insert into ledger_entries (loan_id, kind, amount_paise, entry_date, created_by) values ($1,'payment',10000,'2026-10-11',$2)`, [pay, B]);
await run('2026-10-11');
const day11 = (await entries(pay, 'interest_accrual')).find((e) => e.d === '2026-10-11');
// principal left = 50000 - (10000 - 1670) = 41670 → 41670 × 1000 / 300000 = 138.9 → 139
check('Payment goes to interest first, then principal', day11.a === 139 && day11.note.includes('₹416.70'), `→ ${day11.a} paise, "${day11.note}"`);

// 5. Late interest after due date + grace days, one per day
await closeAll();
const lateLoan = await mk({ start: '2026-10-01', due: '2026-10-05', late: 200, grace: 3 });
await run('2026-10-12');
const lates = await entries(lateLoan, 'late_interest');
check('Late interest only after due + grace, one entry per day', lates.length === 4 && lates[0].d === '2026-10-09' && lates.at(-1).d === '2026-10-12',
  `→ ${lates.map((e) => e.d).join(', ')}`);
console.log('   sample late note:', lates[0]?.note);
const again2 = await run('2026-10-12');
check('No duplicate late entries on a second run', again2.entries_added === 0);

// 6. Terms version 2: earlier days keep the old rate
await closeAll();
const tv = await mk();
await q(`insert into loan_terms (loan_id, version, rate_bps, rate_period, interest_type, late_rate_bps, grace_days, created_by, created_at)
         values ($1, 2, 2000, 'month', 'simple', 0, 0, $2, '2026-10-16 10:00+05:30')`, [tv, B]);
await run('2026-10-20');
const tvs = await entries(tv, 'interest_accrual');
const before = tvs.filter((e) => e.d < '2026-10-16'), after = tvs.filter((e) => e.d >= '2026-10-16');
check('Changing the rate: earlier days keep v1 (10%), later days use v2 (20%)',
  before.length === 15 && before.every((e) => e.a === 167) && after.length === 5 && after.every((e) => e.a === 333),
  `→ v1 days ${before.length}×${before[0]?.a}, v2 days ${after.length}×${after[0]?.a}`);
const terms = await q(`select version, rate_bps from loan_terms where loan_id=$1 order by version`, [tv]);
check('Version 1 is unchanged', terms[0].rate_bps === 1000 && terms[1].rate_bps === 2000);
const tnote = await q(`select note from ledger_entries where loan_id=$1 and kind='terms_change' order by created_at`, [tv]);
console.log('   terms notes:', tnote.map((r) => r.note));

// 7. Catch-up: missed days are filled in one run and match a day-by-day run
await closeAll();
const daily = await mk(); 
for (let d = 1; d <= 20; d++) await run(`2026-10-${String(d).padStart(2, '0')}`);
const dailyBal = await bal(daily);
await closeAll();
const caught = await mk();
await run('2026-10-20');
check('Catch-up after missed days gives the same result as daily runs', (await bal(caught)) === dailyBal, `→ ${dailyBal / 100}`);

// 8. Corrected payment: undone from the correction date
await closeAll();
const rv = await mk();
await run('2026-10-05');
const [p] = await q(`insert into ledger_entries (loan_id, kind, amount_paise, entry_date, created_by) values ($1,'payment',20000,'2026-10-06',$2) returning id`, [rv, B]);
await run('2026-10-08');
await q(`insert into ledger_entries (loan_id, kind, amount_paise, entry_date, reverses_id, created_by) values ($1,'reversal',20000,'2026-10-09',$2,$3)`, [rv, p.id, B]);
await run('2026-10-10');
const rvs = await entries(rv, 'interest_accrual');
const d9 = rvs.find((e) => e.d === '2026-10-09');
check('After a correction, interest is back on the full ₹500', d9.a === 167, `→ day 9: ${d9.a}, note "${d9.note}"`);

// 9. Paid-off loan gets no more interest
await closeAll();
const paid = await mk({ rate: 1000 });
await q(`insert into ledger_entries (loan_id, kind, amount_paise, entry_date, created_by) values ($1,'payment',50000,'2026-10-01',$2)`, [paid, B]);
await run('2026-10-10');
check('A loan paid off on day one gets no interest', (await entries(paid, 'interest_accrual')).length === 0 && (await bal(paid)) === 0);

// 10. Only the server can run the engine
await db.exec(`set role authenticated`);
try { await q(`select accrue_interest('2026-10-30')`); check('App users cannot run the engine', false); }
catch (e) { check('App users cannot run the engine', /permission denied/.test(e.message), `→ ${e.message.split('\n')[0]}`); }
await db.exec(`reset role`);

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
