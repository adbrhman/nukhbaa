-- Test for script 202 (migration 0198): the statements the server runs,
-- copied below with their parameters as function arguments:
-- PostgresNewPlayerReader (the admin's new-players list) and
-- PostgresSupportConversationOpener (support writes first). Rolled back.
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

create function pg_temp.new_players(p_days int, p_limit int)
returns table (id text, email text, role text, status text,
               display_name text, created_at timestamptz,
               phone_accounts int, predictions int, name_hint text)
language sql as $f$
WITH recent AS (
  SELECT u.id, u.email, u.role::text AS role, u.status::text AS status,
         u.display_name, u.created_at
  FROM identity.users u
  WHERE u.role = 'user'
    AND u.created_at >= now() - (p_days * interval '1 day')
  ORDER BY u.created_at DESC
  LIMIT p_limit
),
phones AS (
  SELECT token_key AS phone_key, user_id
  FROM notification.device_token_owners
  UNION
  SELECT install_key, user_id
  FROM identity.install_accounts
),
mine AS (
  SELECT ph.phone_key, ph.user_id
  FROM phones ph
  JOIN recent r ON r.id = ph.user_id
),
sizes AS (
  SELECT m.user_id, max(s.accounts) AS accounts
  FROM mine m
  JOIN (
    SELECT phone_key, count(DISTINCT user_id) AS accounts
    FROM phones
    WHERE phone_key IN (SELECT phone_key FROM mine)
    GROUP BY phone_key
  ) s ON s.phone_key = m.phone_key
  GROUP BY m.user_id
),
predicted AS (
  SELECT pa.user_id, count(*) AS predictions
  FROM prediction.fixture_predictions fp
  JOIN competition.participants pa ON pa.id = fp.participant_id
  WHERE pa.user_id IN (SELECT id FROM recent)
  GROUP BY pa.user_id
)
SELECT r.id::text AS id,
       r.email,
       r.role,
       r.status,
       r.display_name,
       r.created_at,
       coalesce(sz.accounts, 0)::int AS phone_accounts,
       coalesce(pr.predictions, 0)::int AS predictions,
       CASE
         WHEN r.display_name IS NULL OR btrim(r.display_name) = ''
           OR r.display_name = identity.automatic_display_name(r.email)
           THEN 'automatic'
         WHEN r.display_name ~ '[0-9]' THEN 'digits'
         WHEN btrim(r.display_name) !~ '\s' THEN 'one_word'
         WHEN split_part(btrim(r.display_name), ' ', 1) IN (
           'ملك', 'بطل', 'هلال', 'جبل', 'حاطب', 'سائق', 'دكتور', 'الموج',
           'العقيد', 'التبع', 'هنا', 'نجم', 'اسطورة', 'أسطورة', 'عاشق',
           'زعيم', 'قناص', 'المايسترو', 'الملك', 'الزعيم'
         ) THEN 'title'
         WHEN r.display_name ~ '^[A-Za-z ._-]+$' THEN 'latin'
         ELSE NULL
       END AS name_hint
FROM recent r
LEFT JOIN sizes sz ON sz.user_id = r.id
LEFT JOIN predicted pr ON pr.user_id = r.id
ORDER BY r.created_at DESC, r.id
$f$;

create function pg_temp.open_for(p_player uuid) returns text
language sql as $f$
WITH opened AS (
  INSERT INTO support.conversations (player_id)
  VALUES (p_player)
  ON CONFLICT (player_id) DO NOTHING
  RETURNING id
)
SELECT id::text AS id FROM opened
UNION ALL
SELECT id::text FROM support.conversations WHERE player_id = p_player
LIMIT 1
$f$;

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0198_new_players_link'),
  'migration records itself');

do $$
declare
  a uuid := '00000000-0198-4000-8198-000000000001';
  b uuid := '00000000-0198-4000-8198-000000000002';
  c uuid := '00000000-0198-4000-8198-000000000003';
  d uuid := '00000000-0198-4000-8198-000000000004';
  e uuid := '00000000-0198-4000-8198-000000000005';
  old uuid := '00000000-0198-4000-8198-000000000006';
  conv text;
begin
  insert into auth.users (id, email, email_confirmed_at) values
    (a, 'a198@t.io', now()), (b, 'b198@t.io', now()),
    (c, 'c198@t.io', now()), (d, 'd198@t.io', now()),
    (e, 'e198@t.io', now()), (old, 'old198@t.io', now());
  insert into identity.users (id, email, display_name) values
    (a, 'a198@t.io', 'ملك التوقعات'), (b, 'b198@t.io', 'محمد علي'),
    (c, 'c198@t.io', 'Hatib'), (d, 'd198@t.io', 'ابوعابد501'),
    (old, 'old198@t.io', 'قديم جداً');
  insert into identity.users (id, email) values (e, 'e198@t.io');
  update identity.users set created_at = now() - interval '40 days'
   where id = old;
  insert into notification.device_token_owners (token_key, user_id, platform)
  values (md5('tok-198'), a, 'android'), (md5('tok-198'), b, 'android'),
         (md5('tok-198'), c, 'android');

  perform pg_temp.check(
    (select count(*) from pg_temp.new_players(7, 200)
      where id::uuid in (a, b, c, d, e, old)) = 5,
    'the window leaves out an account older than it');
  perform pg_temp.check(
    (select name_hint from pg_temp.new_players(7, 200) where id = a::text)
      = 'title',
    'a title for a first word is hinted');
  perform pg_temp.check(
    (select name_hint from pg_temp.new_players(7, 200) where id = b::text)
      is null,
    'a real-looking name carries no hint');
  perform pg_temp.check(
    (select name_hint from pg_temp.new_players(7, 200) where id = c::text)
      = 'one_word',
    'one word is hinted');
  perform pg_temp.check(
    (select name_hint from pg_temp.new_players(7, 200) where id = d::text)
      = 'digits',
    'digits are hinted');
  perform pg_temp.check(
    (select name_hint from pg_temp.new_players(7, 200) where id = e::text)
      = 'automatic',
    'a name never chosen is hinted');
  perform pg_temp.check(
    (select phone_accounts from pg_temp.new_players(7, 200)
      where id = a::text) = 3,
    'three accounts on his phone');
  perform pg_temp.check(
    (select phone_accounts from pg_temp.new_players(7, 200)
      where id = d::text) = 0,
    'no phone seen is 0');

  conv := pg_temp.open_for(d);
  perform pg_temp.check(conv is not null, 'support opens a conversation');
  perform pg_temp.check(pg_temp.open_for(d) = conv,
    'opening again answers the same conversation');
  perform pg_temp.check(
    (select count(*) from support.conversations where player_id = d) = 1,
    'one conversation per player');
end $$;

rollback;
