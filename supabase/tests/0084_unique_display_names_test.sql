-- End-to-end test for migration 0084: display names are unique by their
-- normalised key; a taken name is refused on update and replaced by the
-- automatic name on insert; automatic names and existing duplicates are left
-- alone. Rolled back at the end.
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

create function pg_temp.mk(n int, email text, name text) returns uuid
language plpgsql as $$
declare v uuid := ('00000000-0000-4000-8084-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into auth.users (id, email, email_confirmed_at) values (v, email, now());
  insert into identity.users (id, email, display_name) values (v, email, name);
  return v;
end $$;

create function pg_temp.name_of(n int) returns text language sql as $$
  select display_name from identity.users
   where id = ('00000000-0000-4000-8084-' || lpad(n::text, 12, '0'))::uuid
$$;

do $$
begin
  perform pg_temp.check(
    identity.display_name_key('  أحمد   علي ') = identity.display_name_key('احمد علي')
    and identity.display_name_key('حمزة') = identity.display_name_key('حمزه')
    and identity.display_name_key('مـصـطـفى') = identity.display_name_key('مصطفي')
    and identity.display_name_key('Ali') = identity.display_name_key('ALI')
    and identity.display_name_key('مُحَمَّد') = identity.display_name_key('محمد'),
    'the key folds case, spaces, tatweel, diacritics and letter variants');
  perform pg_temp.check(
    identity.display_name_key('أحمد') <> identity.display_name_key('محمد'),
    'different names keep different keys');

  perform pg_temp.mk(1, 'a1@t.io', 'أحمد');
  insert into auth.users (id, email, email_confirmed_at)
  values ('00000000-0000-4000-8084-000000000002', 'ahmad.k@t.io', now());
  perform pg_temp.check(
    pg_temp.refusal($q$
      insert into identity.users (id, email, display_name)
      values ('00000000-0000-4000-8084-000000000002', 'ahmad.k@t.io', 'احمد')
    $q$) = 'none'
    and pg_temp.name_of(2) = 'ahmad.k',
    'a first sign-in with a taken name gets the automatic name instead of failing');

  perform pg_temp.check(
    pg_temp.refusal($q$
      update identity.users set display_name = ' أحمـد '
       where id = '00000000-0000-4000-8084-000000000002'
    $q$) = '23505/users_display_name_taken',
    'choosing a taken name is refused by name');

  update identity.users set display_name = 'أحمد الثاني'
   where id = '00000000-0000-4000-8084-000000000002';
  perform pg_temp.check(pg_temp.name_of(2) = 'أحمد الثاني', 'a free name is accepted');

  -- Automatic names are never counted: two addresses share 'sam'.
  perform pg_temp.mk(3, 'sam@one.io', 'sam');
  perform pg_temp.mk(4, 'sam@two.io', 'sam');
  perform pg_temp.check(pg_temp.name_of(4) = 'sam', 'two automatic names may coincide');

  -- Nor may a chosen name be blocked by someone's automatic name.
  update identity.users set display_name = 'Sam'
   where id = '00000000-0000-4000-8084-000000000003';
  perform pg_temp.check(pg_temp.name_of(3) = 'Sam', 'an automatic name does not hold a name');

  -- A pair that already shares a name (from before 0084) is left alone, and
  -- either may still touch other columns.
  alter table identity.users disable trigger users_unique_display_name;
  perform pg_temp.mk(5, 'old1@t.io', 'خالد');
  perform pg_temp.mk(6, 'old2@t.io', 'خالد');
  alter table identity.users enable trigger users_unique_display_name;
  -- The sign-in upsert (PostgresUserDirectory.ensureUser) of one of them
  -- keeps its name: the conflict path never writes display_name.
  insert into identity.users (id, email, role, status, display_name)
  values ('00000000-0000-4000-8084-000000000005', 'old1@t.io', 'user', 'active', 'خالد')
  on conflict (id) do update
    set email = coalesce(excluded.email, identity.users.email), updated_at = now();
  perform pg_temp.check(pg_temp.name_of(5) = 'خالد', 'signing in again keeps an existing duplicate name');
  update identity.users set email = 'old2b@t.io'
   where id = '00000000-0000-4000-8084-000000000006';
  perform pg_temp.check(pg_temp.name_of(6) = 'خالد', 'an existing duplicate is not renamed by the guard');
  update identity.users set display_name = 'خالد سعيد'
   where id = '00000000-0000-4000-8084-000000000006';
  perform pg_temp.check(pg_temp.name_of(6) = 'خالد سعيد', 'renaming one of a pair resolves it');
end $$;

rollback;
