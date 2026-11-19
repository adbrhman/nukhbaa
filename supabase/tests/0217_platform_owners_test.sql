-- End-to-end test for migration 0217: the owner seats. One primary at
-- most; a seat needs an existing account; an account that is no active
-- admin, or was erased, holds no active seat; the order the server reads
-- (primary first) is the order PostgresOwnerRegistry asks for. Rolled back
-- at the end.
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

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0217-4000-8217-000000000001', 'po1@t.io', now()),
  ('00000000-0217-4000-8217-000000000002', 'po2@t.io', now()),
  ('00000000-0217-4000-8217-000000000003', 'po3@t.io', now()),
  ('00000000-0217-4000-8217-000000000004', 'po4@t.io', now());
insert into identity.users (id, email, display_name, role) values
  ('00000000-0217-4000-8217-000000000001', 'po1@t.io', 'PO One', 'admin'),
  ('00000000-0217-4000-8217-000000000002', 'po2@t.io', 'PO Two', 'admin'),
  ('00000000-0217-4000-8217-000000000003', 'po3@t.io', 'PO Three', 'user'),
  ('00000000-0217-4000-8217-000000000004', 'po4@t.io', 'PO Four', 'admin');

do $$
declare
  u1 uuid := '00000000-0217-4000-8217-000000000001';
  u2 uuid := '00000000-0217-4000-8217-000000000002';
  u3 uuid := '00000000-0217-4000-8217-000000000003';
  u4 uuid := '00000000-0217-4000-8217-000000000004';
  ids text;
begin
  -- The backup is seated first: the order is by seat, not by time.
  insert into admin.platform_owners (user_id, seat) values (u2, 'backup');
  insert into admin.platform_owners (user_id, seat) values (u1, 'primary');

  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into admin.platform_owners (user_id, seat) values (%L, %L)',
      u4, 'primary'))
      = '23505/platform_owners_one_primary',
    'a second primary seat is refused');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into admin.platform_owners (user_id, seat) values (%L, %L)',
      u4, 'owner'))
      = '23514/platform_owners_seat_check',
    'a seat is primary or backup');
  perform pg_temp.check(
    pg_temp.refusal(format(
      'insert into admin.platform_owners (user_id, seat) values (%L, %L)',
      '00000000-0217-4000-8217-0000000000ff', 'backup'))
      = '23503/platform_owners_user_id_fkey',
    'a seat needs an existing account');

  -- The registry's own query (PostgresOwnerRegistry).
  select string_agg(user_id::text, ',' order by (seat = 'primary') desc,
                    added_at, user_id)
    into ids
    from admin.active_owners;
  perform pg_temp.check(
    ids = u1::text || ',' || u2::text,
    'the primary is read first, then the backup');

  -- A seated account that is a plain player acts as no owner.
  insert into admin.platform_owners (user_id, seat) values (u3, 'backup');
  perform pg_temp.check(
    not exists (select 1 from admin.active_owners where user_id = u3),
    'a seat held by a player is not active');

  -- A suspended admin acts as no owner.
  update identity.users set status = 'suspended' where id = u2;
  perform pg_temp.check(
    not exists (select 1 from admin.active_owners where user_id = u2),
    'a suspended account holds no active seat');
  update identity.users set status = 'active' where id = u2;

  -- An erased account acts as no owner.
  update identity.users set deleted_at = now() where id = u2;
  perform pg_temp.check(
    not exists (select 1 from admin.active_owners where user_id = u2),
    'an erased account holds no active seat');

  -- The account of a seat cannot be removed under it.
  perform pg_temp.check(
    pg_temp.refusal(format(
      'delete from identity.users where id = %L', u1))
      like '23503/%',
    'an account with a seat is not deleted');
end $$;

rollback;
