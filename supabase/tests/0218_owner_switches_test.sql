-- End-to-end test for migration 0218: the owners' switches. The crowning
-- switch starts on; crowning_pause.sql and crowning_resume.sql turn it off
-- and on with their reason; a blank reason or an unknown switch is
-- refused; the crown notices take the kind 'held', once per month. Run
-- from the repository root, as db-tests does. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

-- The SQLSTATE and constraint name [stmt] raises, or 'none'.
create function pg_temp.refusal(stmt text) returns text
language plpgsql as $$
declare
  v_state text;
  v_constraint text;
begin
  execute stmt;
  return 'none';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate,
                          v_constraint = constraint_name;
  return v_state || '/' || coalesce(v_constraint, '');
end $$;

select pg_temp.check(
  (select is_on from ops.owner_switches where switch_key = 'crowning'),
  'the crowning switch starts on');

\i supabase/queries/crowning_pause.sql
select pg_temp.check(
  (select not is_on and reason is not null
     from ops.owner_switches where switch_key = 'crowning'),
  'crowning_pause.sql turns it off with its reason');

\i supabase/queries/crowning_pause.sql
select pg_temp.check(
  (select not is_on from ops.owner_switches where switch_key = 'crowning'),
  'crowning_pause.sql run twice keeps it off');

\i supabase/queries/crowning_resume.sql
select pg_temp.check(
  (select is_on from ops.owner_switches where switch_key = 'crowning'),
  'crowning_resume.sql turns it back on');

select pg_temp.check(
  pg_temp.refusal(
    'update ops.owner_switches set reason = $$  $$ where switch_key = $$crowning$$')
    = '23514/owner_switches_reason_not_blank',
  'a blank reason is refused');

select pg_temp.check(
  pg_temp.refusal(
    'insert into ops.owner_switches (switch_key) values ($$chat$$)')
    = '23514/owner_switches_key_check',
  'a switch this batch does not know is refused');

do $$
declare
  s uuid;
begin
  select id into s from competition.seasons limit 1;
  if s is null then
    raise notice 'ok - no season in this database: the held notice is checked by its constraint alone';
    perform pg_temp.check(
      exists (
        select 1 from pg_constraint
         where conname = 'month_crown_notices_kind_check'
           and pg_get_constraintdef(oid) like '%held%'),
      'the crown notices take the kind held');
    return;
  end if;
  insert into competition.month_crown_notices (season_id, kind, signature)
  values (s, 'held', 'held');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into competition.month_crown_notices (season_id, kind, signature) values (%L, %L, %L)',
      s, 'held', 'held'))
      = '23505/month_crown_notices_pkey',
    'the held notice is kept once per month');
end $$;

rollback;
