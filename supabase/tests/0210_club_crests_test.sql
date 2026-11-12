-- Test for script 265 (migration 0210): the club crests, their switch and
-- their log, through the statements PostgresCrestCatalog runs (copied
-- below with their parameters as function arguments). Rolled back at the
-- end.
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

create function pg_temp.list()
returns table (clubs_enabled boolean, slug text, object_path text,
               status text, reason text, complainant text,
               changed_at timestamptz)
language sql as $f$
SELECT s.clubs_enabled, c.slug, c.object_path, c.status, c.reason,
       c.complainant, c.changed_at
FROM media.crest_settings s
LEFT JOIN media.club_crests c ON true
WHERE s.id
ORDER BY c.slug
$f$;

create function pg_temp.move(p_slug text, p_from text, p_to text,
                             p_action text, p_reason text,
                             p_complainant text, p_by uuid)
returns int
language sql as $f$
WITH moved AS (
  UPDATE media.club_crests
  SET status = p_to,
      reason = p_reason,
      complainant = nullif(p_complainant, ''),
      changed_at = now(),
      changed_by = p_by::uuid
  WHERE slug = p_slug
    AND status = ANY (string_to_array(p_from, ','))
  RETURNING slug
), logged AS (
  INSERT INTO media.crest_events (slug, action, reason, complainant, actor_id)
  SELECT m.slug, p_action, p_reason, nullif(p_complainant, ''), p_by::uuid
  FROM moved m
  RETURNING id
)
SELECT count(*)::int AS moved FROM logged
$f$;

create function pg_temp.switch(p_enabled boolean, p_reason text, p_by uuid)
returns setof bigint
language sql as $f$
WITH switched AS (
  UPDATE media.crest_settings
  SET clubs_enabled = p_enabled::boolean,
      changed_at = now(),
      changed_by = p_by::uuid
  WHERE id
  RETURNING id
)
INSERT INTO media.crest_events (action, reason, actor_id)
SELECT CASE WHEN p_enabled::boolean THEN 'clubs_on' ELSE 'clubs_off' END,
       p_reason, p_by::uuid
FROM switched
RETURNING id
$f$;

create function pg_temp.events(p_limit int)
returns table (slug text, action text, reason text, complainant text,
               at timestamptz)
language sql as $f$
SELECT e.slug, e.action, e.reason, e.complainant, e.at
FROM media.crest_events e
ORDER BY e.at DESC, e.id DESC
LIMIT p_limit
$f$;

insert into auth.users (id, email, email_confirmed_at)
values ('00000000-0000-4000-8210-000000000001', 'o210@t.io', now());
insert into identity.users (id, email, display_name, role)
values ('00000000-0000-4000-8210-000000000001', 'o210@t.io', 'Owner', 'admin');

do $$
declare
  o uuid := '00000000-0000-4000-8210-000000000001';
begin
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0210_club_crests'),
    '0210 records itself');
  perform pg_temp.check(
    (select count(*) from media.club_crests where status = 'active') = 235,
    'the app''s 235 club crests, active');
  perform pg_temp.check(
    not exists (select 1 from media.club_crests where slug in
      ('saudi-arabia', 'egypt', 'switzerland', 'yemen', 'morocco')),
    'no country flag among them');
  perform pg_temp.check(
    (select object_path from media.club_crests where slug = 'arsenal')
      ~ '^clubs/arsenal\.[0-9a-f]{8}\.png$',
    'a crest''s file is named by its content');
  perform pg_temp.check(
    (select public from storage.buckets where id = 'crests'),
    'the bucket crests is public');
  perform pg_temp.check(
    (select bool_and(clubs_enabled) from pg_temp.list())
      and (select count(*) from pg_temp.list()) = 235,
    'the list: every crest, the switch on');

  perform pg_temp.check(
    pg_temp.move('arsenal', 'active', 'hidden', 'hidden', 'شكوى', 'club@x', o) = 1,
    'an active crest is hidden');
  perform pg_temp.check(
    pg_temp.move('arsenal', 'active', 'hidden', 'hidden', 'شكوى', '', o) = 0,
    'a hidden crest is not hidden twice');
  perform pg_temp.check(
    pg_temp.move('nope', 'active', 'hidden', 'hidden', 'x', '', o) = 0,
    'an unknown crest moves nothing');
  perform pg_temp.check(
    (select status || '|' || complainant from media.club_crests
      where slug = 'arsenal') = 'hidden|club@x',
    'the status and the complainant are kept');
  perform pg_temp.check(
    pg_temp.move('arsenal', 'active,hidden', 'deleted', 'deleted', 'حذف', '', o) = 1,
    'a hidden crest is deleted');
  perform pg_temp.check(
    (select complainant from media.club_crests where slug = 'arsenal') is null,
    'an empty complainant is none');

  perform pg_temp.check((select count(*) from pg_temp.switch(false, 'مراجعة', o)) = 1,
    'club crests turned off');
  perform pg_temp.check(not (select clubs_enabled from media.crest_settings),
    'the switch is off');

  perform pg_temp.check(
    (select string_agg(action, ',') from pg_temp.events(50)) = 'clubs_off,deleted,hidden',
    'the log, newest first');
  perform pg_temp.check(
    (select count(*) from pg_temp.events(2)) = 2, 'the log keeps its limit');
end $$;

rollback;
