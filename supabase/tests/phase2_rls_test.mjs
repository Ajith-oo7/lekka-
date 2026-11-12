import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
const db = new PGlite();
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8').replace(/create extension if not exists pgcrypto;/, '');
const B = '11111111-1111-1111-1111-111111111111', O = '22222222-2222-2222-2222-222222222222';
const q = async (sql, p) => (await db.query(sql, p)).rows;
const as = async (uid) => { await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid}',false); set role authenticated;`); };
const expectFail = async (label, fn) => { try { await fn(); console.log('FAIL (should have errored):', label); } catch (e) { console.log('ok, blocked:', label, '->', e.message.split('\n')[0]); } };
await db.exec(`
create schema auth;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create role authenticated;
`);
await db.exec(schema);
await db.exec(`grant usage on schema public, auth to authenticated;
grant all on all tables in schema public to authenticated;
grant execute on all functions in schema public, auth to authenticated;`);
await db.exec(`insert into auth.users values ('${B}', '{"name":"Bala","language":"te"}'), ('${O}', '{"name":"Other"}');`);
console.log('profiles:', await q('select name, language from profiles order by name'));

await as(B);
const [g] = await q(`insert into groups (owner_id, name) values ($1, 'Family') returning id`, [B]);
const [c] = await q(`insert into contacts (owner_id, name) values ($1, 'Vasu') returning id`, [B]);
const [{ create_loan: loanId }] = await q(`select create_loan($1,$2,50000,current_date,current_date+30,1000,'month','simple',0,0)`, [g.id, c.id]);
console.log('records after create:', (await q('select kind, amount_paise, note from ledger_entries order by created_at')));
const bal = async () => (await q('select outstanding_paise from loan_balances where loan_id=$1', [loanId]))[0].outstanding_paise;
console.log('balance:', await bal());
const [pay] = await q(`insert into ledger_entries (loan_id, kind, amount_paise, created_by) values ($1,'payment',10000,$2) returning id`, [loanId, B]);
console.log('balance after ₹100 payment:', await bal());
await q(`insert into ledger_entries (loan_id, kind, amount_paise, reverses_id, created_by) values ($1,'reversal',10000,$2,$3)`, [loanId, pay.id, B]);
console.log('balance after correction:', await bal(), ' entries:', (await q('select count(*)::int n from ledger_entries'))[0].n);
await expectFail('second correction of same payment', () => q(`insert into ledger_entries (loan_id, kind, amount_paise, reverses_id, created_by) values ($1,'reversal',10000,$2,$3)`, [loanId, pay.id, B]));
await expectFail('edit a ledger row', () => q(`update ledger_entries set amount_paise = 1 where id=$1`, [pay.id]));
await expectFail('delete a ledger row', () => q(`delete from ledger_entries where id=$1`, [pay.id]));
console.log('payment row still:', (await q('select amount_paise from ledger_entries where id=$1',[pay.id]))[0]);
await expectFail('client adds interest entry', () => q(`insert into ledger_entries (loan_id, kind, amount_paise, created_by) values ($1,'interest_accrual',5,$2)`, [loanId, B]));

await as(O);
console.log('Other sees loans:', (await q('select count(*)::int n from loans'))[0].n,
  ' ledger:', (await q('select count(*)::int n from ledger_entries'))[0].n,
  ' groups:', (await q('select count(*)::int n from groups'))[0].n,
  ' contacts:', (await q('select count(*)::int n from contacts'))[0].n,
  ' balances:', (await q('select count(*)::int n from loan_balances'))[0].n);
await expectFail("Other adds loan to Bala's group", () => q(`select create_loan($1,$2,100,current_date,current_date,0,'month','simple',0,0)`, [g.id, c.id]));
const [og] = await q(`insert into groups (owner_id, name) values ($1, 'Mine') returning id`, [O]);
await expectFail("Other uses Bala's contact in own group", () => q(`select create_loan($1,$2,100,current_date,current_date,0,'month','simple',0,0)`, [og.id, c.id]));
await expectFail("Other records payment on Bala's loan", () => q(`insert into ledger_entries (loan_id, kind, amount_paise, created_by) values ($1,'payment',100,$2)`, [loanId, O]));
