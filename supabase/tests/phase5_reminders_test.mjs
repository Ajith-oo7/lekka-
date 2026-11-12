import { setup, U } from './harness.mjs';
const { db, q, as, admin, check, blocked, done } = await setup(process.argv.slice(2));
await db.exec(`insert into auth.users values ('${U.bala}','{"name":"Bala"}'),('${U.vasu}','{"name":"Vasu K","language":"te"}'),('${U.third}','{"name":"Third"}');`);
const DUE = '2026-10-20';
await as(U.bala);
const [g] = await q(`insert into groups (owner_id,name) values ($1,'Family') returning id`, [U.bala]);
const [c] = await q(`insert into contacts (owner_id,name) values ($1,'Vasu') returning id`, [U.bala]);
const [c2] = await q(`insert into contacts (owner_id,name) values ($1,'Ramu') returning id`, [U.bala]);
const mk = async (contact, extra = '') => (await q(`select create_loan($1,$2,50000,'2026-10-01'::date,$3::date,1000,'month','simple',200,0${extra}) id`, [g.id, contact, DUE]))[0].id;
const shared = await mk(c.id);
const solo = await mk(c2.id);          // Ramu has no app
const code = (await q(`select create_invite($1) c`, [shared]))[0].c;
await as(U.vasu);
await q(`select join_with_code($1)`, [code]);

await admin();
const run = async (day) => q(`select * from queue_reminders($1::date)`, [day]);
const kinds = (rows, loan) => rows.filter((r) => r.loan_id === loan).map((r) => r.kind);

check('3 days before the due date: nothing', (await run('2026-10-17')).length === 0);
const d18 = await run('2026-10-18');
check('2 days before: "due soon"', kinds(d18, shared).join() === 'due_soon');
const sharedRow = d18.find((r) => r.loan_id === shared), soloRow = d18.find((r) => r.loan_id === solo);
check('Shared loan: the borrower gets it, in Telugu, naming the lender',
  sharedRow.user_id === U.vasu && sharedRow.language === 'te' && sharedRow.person_name === 'Bala' && sharedRow.to_lender === false,
  `→ ${sharedRow.language}, ${sharedRow.person_name}`);
check('Solo-lender loan: only the lender gets it, naming the contact',
  soloRow.user_id === U.bala && soloRow.to_lender === true && soloRow.person_name === 'Ramu' && d18.filter((r) => r.loan_id === solo).length === 1);
check('Running again the same day sends nothing', (await run('2026-10-18')).length === 0);
check('1 day before: nothing', (await run('2026-10-19')).length === 0);
check('On the due date: "due today"', kinds(await run('2026-10-20'), shared).join() === 'due_today');

await q(`select accrue_interest('2026-10-22')`);
const d21 = await run('2026-10-21'), d22 = await run('2026-10-22'), d23 = await run('2026-10-23');
check('Every day after the due date: "overdue"', [d21, d22, d23].every((d) => kinds(d, shared).join() === 'overdue'));
const od = d23.find((r) => r.loan_id === shared);
check('The overdue reminder carries the late interest added and the balance', Number(od.late_paise) > 0 && Number(od.balance_paise) > 50000,
  `→ late ${od.late_paise} paise, balance ${od.balance_paise} paise`);

// A paid or closed loan gets no reminders
const bal = Number((await q(`select outstanding_paise b from loan_balances where loan_id=$1`, [solo]))[0].b);
await q(`insert into ledger_entries (loan_id,kind,amount_paise,entry_date,created_by) values ($1,'payment',$2,'2026-10-23',$3)`, [solo, bal, U.bala]);
await q(`update loans set status='closed' where id=$1`, [shared]);
check('Paid-off and closed loans get no reminders', (await run('2026-10-24')).length === 0);
await q(`update loans set status='active' where id=$1`, [shared]);

// Pings
await as(U.vasu);
await blocked('The borrower cannot ping', () => q(`select send_ping($1)`, [shared]), /PING_NOT_ALLOWED/);
await as(U.third);
await blocked('A stranger cannot ping', () => q(`select send_ping($1)`, [shared]), /PING_NOT_ALLOWED/);
await blocked('App users cannot run the daily reminders', () => q(`select * from queue_reminders()`), /permission denied/);
await as(U.bala);
await blocked('No ping on a solo-lender loan (the borrower has no app)', () => q(`select send_ping($1)`, [solo]), /PING_NOT_ALLOWED/);
for (let i = 0; i < 3; i++) await q(`select send_ping($1)`, [shared]);
await blocked('A 4th ping on the same day is refused', () => q(`select send_ping($1)`, [shared]), /PING_LIMIT/);
check('Bala does not see Vasu\'s reminders', (await q(`select count(*)::int n from notifications where user_id=$1`, [U.vasu]))[0].n === 0);

await as(U.vasu);
const mine = await q(`select kind, person_name from notifications order by created_at`);
check('Vasu\'s Reminders list has the reminders and 3 pings',
  mine.filter((n) => n.kind === 'ping').length === 3 && mine.filter((n) => n.kind === 'overdue').length === 3 && mine.every((n) => n.person_name === 'Bala'),
  `→ ${mine.map((n) => n.kind).join(', ')}`);
await blocked('Vasu cannot write reminders himself', () => q(`insert into notifications (user_id,loan_id,kind) values ($1,$2,'ping')`, [U.vasu, shared]), /row-level security/);

// Device tokens
await q(`select register_device_token('tok-phone-1','android')`);
await as(U.bala);
await q(`select register_device_token('tok-phone-1','android')`);   // same phone, new account
check('A phone\'s token moves to the account now signed in on it', (await q(`select count(*)::int n from device_tokens where token='tok-phone-1'`))[0].n === 1);
await as(U.vasu);
check('...and the old account no longer has it', (await q(`select count(*)::int n from device_tokens`))[0].n === 0);
done();
