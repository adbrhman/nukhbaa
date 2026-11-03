-- Test for PostgresUserDirectory._replaceDisplayNameSql (batch 212, audit
-- 33): a player's one-time name is written only while the stored name is
-- still the one his request read. Of two requests that both read the
-- automatic name, the first writes and the second matches nothing, so it
-- cannot overwrite the first one's choice; a name another player holds is
-- still refused by migration 0084. Keep the body identical to the adapter's
-- constant (script 215 compares them). Rolled back at the end.
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

-- PostgresUserDirectory._replaceDisplayNameSql
create function pg_temp.replace_name(p_id uuid, p_expected text, p_displayName text)
returns table (r_id uuid, r_email text, r_role text, r_status text,
               r_display_name text, r_avatar_mime text,
               r_avatar_updated_at timestamptz)
language sql as $q$
    UPDATE identity.users
    SET display_name = p_displayName,
        updated_at = now()
    WHERE id = p_id
      AND display_name = p_expected
    RETURNING id, email, role::text, status::text, display_name,
              avatar_mime, avatar_updated_at
$q$;

create function pg_temp.name_of(n int) returns text language sql as $$
  select display_name from identity.users
   where id = ('00000000-0215-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;

create function pg_temp.uid(n int) returns uuid language sql as $$
  select ('00000000-0215-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;

insert into auth.users (id, email, email_confirmed_at) values
  (pg_temp.uid(1), 'chooser@t.io', now()),
  (pg_temp.uid(2), 'holder@t.io', now()),
  (pg_temp.uid(3), 'late@t.io', now());
-- 1 and 3 still carry the automatic name; 2 chose his long ago.
insert into identity.users (id, email, display_name) values
  (pg_temp.uid(1), 'chooser@t.io', 'chooser'),
  (pg_temp.uid(2), 'holder@t.io', 'Name Holder'),
  (pg_temp.uid(3), 'late@t.io', 'late');

do $$
declare
  v_rows int;
  v_name text;
begin
  -- The first of two requests that both read the automatic name.
  select count(*), max(r_display_name) into v_rows, v_name
    from pg_temp.replace_name(pg_temp.uid(1), 'chooser', 'First Choice');
  perform pg_temp.check(v_rows = 1 and v_name = 'First Choice',
    'the first choice is written and returned');
  perform pg_temp.check(pg_temp.name_of(1) = 'First Choice',
    'the first choice is stored');

  -- The second read the same automatic name: it matches nothing.
  select count(*) into v_rows
    from pg_temp.replace_name(pg_temp.uid(1), 'chooser', 'Second Choice');
  perform pg_temp.check(v_rows = 0,
    'a request that read the old name matches no row');
  perform pg_temp.check(pg_temp.name_of(1) = 'First Choice',
    'the first choice is not overwritten');

  -- A request that read the stored name exactly is the only one that writes.
  select count(*) into v_rows
    from pg_temp.replace_name(pg_temp.uid(2), 'holder', 'Not Mine');
  perform pg_temp.check(v_rows = 0 and pg_temp.name_of(2) = 'Name Holder',
    'a chosen name is never replaced through the automatic one');

  -- The expected name of one player never writes another player's row.
  select count(*) into v_rows
    from pg_temp.replace_name(pg_temp.uid(3), 'First Choice', 'Borrowed');
  perform pg_temp.check(v_rows = 0 and pg_temp.name_of(3) = 'late',
    'the expected name is compared on the request''s own row');

  -- Migration 0084 still refuses a name another player holds, by its key.
  perform pg_temp.check(
    pg_temp.refusal($s$select * from pg_temp.replace_name(
       pg_temp.uid(3), 'late', '  name   HOLDER ')$s$)
      = '23505/users_display_name_taken',
    'a taken name is refused as users_display_name_taken');
  perform pg_temp.check(pg_temp.name_of(3) = 'late',
    'the refused request left the automatic name');

  -- A free name goes through for him.
  select count(*) into v_rows
    from pg_temp.replace_name(pg_temp.uid(3), 'late', 'Late Comer');
  perform pg_temp.check(v_rows = 1 and pg_temp.name_of(3) = 'Late Comer',
    'a free name is written');
end $$;

rollback;
