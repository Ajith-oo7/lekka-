// Shared test harness: schema.sql in an in-memory Postgres with a stand-in for Supabase Auth.
import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
export async function setup(extraSql = []) {
  const db = new PGlite();
  const read = (p) => fs.readFileSync(p, 'utf8');
  await db.exec(`create schema auth;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
create role authenticated; create role anon; create role service_role;`);
  await db.exec(read(new URL('../schema.sql', import.meta.url)).replace(/create extension if not exists pgcrypto;/, ''));
  for (const f of extraSql) await db.exec(read(f));
  await db.exec(`grant usage on schema public, auth to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;`);
  const q = async (sql, p) => (await db.query(sql, p)).rows;
  const as = async (uid) => { await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid}',false); set role authenticated;`); };
  const admin = async () => { await db.exec(`reset role`); };
  let pass = 0, fail = 0;
  const check = (label, ok, info = '') => { ok ? pass++ : fail++; console.log(ok ? 'PASS' : 'FAIL', label, info); };
  const blocked = async (label, fn, pattern) => {
    try { await fn(); check(label, false, '→ was allowed'); }
    catch (e) { const m = e.message.split('\n')[0]; check(label, pattern ? pattern.test(m) : true, `→ ${m}`); }
  };
  const done = () => { console.log(`\n${pass} passed, ${fail} failed`); if (fail) process.exit(1); };
  return { db, q, as, admin, check, blocked, done };
}
export const U = {
  bala: '11111111-1111-1111-1111-111111111111',
  vasu: '22222222-2222-2222-2222-222222222222',
  third: '33333333-3333-3333-3333-333333333333',
};
