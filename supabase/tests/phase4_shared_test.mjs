import { setup, U } from './harness.mjs';
const { db, q, as, admin, check, blocked, done } = await setup(process.argv.slice(2));
await db.exec(`insert into auth.users values ('${U.bala}','{"name":"Bala"}'),('${U.vasu}','{"name":"Vasu K","language":"te"}'),('${U.third}','{"name":"Third"}');`);

await as(U.bala);
const [g] = await q(`insert into groups (owner_id,name) values ($1,'Family') returning id`, [U.bala]);
const [c] = await q(`insert into contacts (owner_id,name) values ($1,'Vasu') returning id`, [U.bala]);
const loan = (await q(`select create_loan($1,$2,50000,current_date,current_date+30,1000,'month','simple',0,0) id`, [g.id, c.id]))[0].id;
const code = (await q(`select create_invite($1) c`, [loan]))[0].c;
check('Lender gets a 10-character invite code', /^[0-9A-F]{10}$/.test(code), `→ ${code}`);
check('Asking again returns the same code', (await q(`select create_invite($1) c`, [loan]))[0].c === code);
await blocked('Lender cannot use their own code', () => q(`select join_with_code($1)`, [code]), /INVITE_OWN/);

await as(U.third);
await blocked('A stranger cannot make an invite for Bala\'s loan', () => q(`select create_invite($1)`, [loan]), /INVITE_NOT_ALLOWED/);
await blocked('A wrong code is refused', () => q(`select join_with_code('ZZZZZZZZZZ')`), /INVITE_INVALID/);
check('Third account cannot read invites', (await q(`select count(*)::int n from invites`))[0].n === 0);

await as(U.vasu);
check('Before joining, Vasu sees nothing', (await q(`select count(*)::int n from loans`))[0].n === 0);
const joined = (await q(`select join_with_code($1) id`, [` ${code.slice(0, 5).toLowerCase()}-${code.slice(5)} `]))[0].id;
check('Vasu joins with the code (spaces, dash and lower case accepted)', joined === loan);
const bal = async () => Number((await q(`select outstanding_paise b from loan_balances where loan_id=$1`, [loan]))[0].b);
check('Vasu sees the loan and the same balance', (await q(`select count(*)::int n from loans`))[0].n === 1 && (await bal()) === 50000);
check('Vasu sees Records', (await q(`select count(*)::int n from ledger_entries`))[0].n === 2);
check('Vasu sees the group', (await q(`select name from groups`))[0]?.name === 'Family');
const people = await q(`select lender_name, borrower_name from loan_people()`);
check('Vasu sees the lender\'s name', people[0].lender_name === 'Bala' && people[0].borrower_name === 'Vasu', `→ ${JSON.stringify(people[0])}`);
await blocked('The code cannot be used twice', () => q(`select join_with_code($1)`, [code]), /INVITE_INVALID/);

const [t1] = await q(`select id, accepted_at from loan_terms where loan_id=$1`, [loan]);
await blocked('Vasu cannot add a terms version', () => q(`insert into loan_terms (loan_id,version,rate_bps,created_by) values ($1,2,1,$2)`, [loan, U.vasu]), /row-level security/);
await q(`update loan_terms set rate_bps = 1 where id=$1`, [t1.id]);
check('Vasu cannot edit existing terms', (await q(`select rate_bps from loan_terms where id=$1`, [t1.id]))[0].rate_bps === 1000);
await blocked('Vasu cannot record a payment', () => q(`insert into ledger_entries (loan_id,kind,amount_paise,created_by) values ($1,'payment',100,$2)`, [loan, U.vasu]), /row-level security/);
await q(`update loans set status='closed' where id=$1`, [loan]);
check('Vasu cannot close the loan', (await q(`select status from loans where id=$1`, [loan]))[0].status === 'active');
await q(`select accept_terms($1)`, [t1.id]);
check('Vasu can accept the terms', (await q(`select accepted_at from loan_terms where id=$1`, [t1.id]))[0].accepted_at !== null);

await as(U.bala);
check('Bala sees the acceptance', (await q(`select accepted_at from loan_terms where id=$1`, [t1.id]))[0].accepted_at !== null);
await q(`select accept_terms(id) from loan_terms where loan_id=$1`, [loan]);
const [pay] = await q(`insert into ledger_entries (loan_id,kind,amount_paise,created_by) values ($1,'payment',10000,$2) returning id`, [loan, U.bala]);
await blocked('Bala cannot confirm his own entry', () => q(`insert into entry_confirmations (entry_id,user_id) values ($1,$2)`, [pay.id, U.bala]), /row-level security/);
await blocked('Bala cannot change the loan amount', () => q(`update loans set principal_paise = 1 where id=$1`, [loan]), /Only the due date and status/);
await blocked('Bala cannot swap the borrower', () => q(`update loans set borrower_user_id = null where id=$1`, [loan]), /Only the due date and status/);
await blocked('No second invite once the borrower has joined', () => q(`select create_invite($1)`, [loan]), /INVITE_NOT_ALLOWED/);
check('Bala\'s contact is linked to Vasu\'s account', (await q(`select linked_user_id from contacts where id=$1`, [c.id]))[0].linked_user_id === U.vasu);

await as(U.vasu);
check('Vasu sees the payment and balance ₹400', (await bal()) === 40000);
await q(`insert into entry_confirmations (entry_id,user_id) values ($1,$2)`, [pay.id, U.vasu]);
const [first] = await q(`select id from ledger_entries where loan_id=$1 and kind='loan_created'`, [loan]);
await blocked('Only payments can be confirmed', () => q(`insert into entry_confirmations (entry_id,user_id) values ($1,$2)`, [first.id, U.vasu]), /row-level security/);
await as(U.bala);
check('Bala sees Vasu\'s confirmation', (await q(`select count(*)::int n from entry_confirmations where entry_id=$1`, [pay.id]))[0].n === 1);

await as(U.third);
const seen = await q(`select (select count(*) from loans)::int l, (select count(*) from ledger_entries)::int e, (select count(*) from loan_terms)::int t,
  (select count(*) from entry_confirmations)::int c, (select count(*) from groups)::int g, (select count(*) from loan_people())::int p`);
check('A third account sees nothing', Object.values(seen[0]).every((n) => n === 0), `→ ${JSON.stringify(seen[0])}`);

// Solo borrower mode
await as(U.vasu);
const [vg] = await q(`insert into groups (owner_id,name) values ($1,'My loans') returning id`, [U.vasu]);
const [vc] = await q(`insert into contacts (owner_id,name) values ($1,'Ravi') returning id`, [U.vasu]);
const solo = (await q(`select create_loan($1,$2,20000,current_date,current_date+30,500,'month','simple',0,0,true) id`, [vg.id, vc.id]))[0].id;
const [sl] = await q(`select lender_user_id, borrower_user_id from loans where id=$1`, [solo]);
check('Solo borrower loan: Vasu is the borrower, no lender account', sl.lender_user_id === null && sl.borrower_user_id === U.vasu);
await q(`insert into ledger_entries (loan_id,kind,amount_paise,created_by) values ($1,'payment',5000,$2)`, [solo, U.vasu]);
check('Vasu can record his own payment on it', Number((await q(`select outstanding_paise b from loan_balances where loan_id=$1`, [solo]))[0].b) === 15000);
const sp = (await q(`select * from loan_people() where loan_id=$1`, [solo]))[0];
check('Names for the solo borrower loan', sp.lender_name === 'Ravi' && sp.borrower_name === 'Vasu K', `→ ${JSON.stringify(sp)}`);
await blocked('No invite on a solo borrower loan', () => q(`select create_invite($1)`, [solo]), /INVITE_NOT_ALLOWED/);
await as(U.bala);
check('Bala cannot see Vasu\'s solo loan', (await q(`select count(*)::int n from loans where id=$1`, [solo]))[0].n === 0);
done();
