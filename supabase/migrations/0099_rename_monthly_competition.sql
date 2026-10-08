-- ============================================================================
-- Migration 0099: the monthly competition's name
--
-- MODIFY-ONLY: one display name. Nothing is deleted. The one competition
-- that holds every monthly season was created in September and named
-- "شهر 9", which reads as "September" on every admin screen while it holds
-- 09/2026, 10/2026, 11/2026... (requested 2026-10-08). It becomes
-- "المسابقة الشهرية". The name is display only: no code matches on it
-- (checked 2026-10-08). Its id, seasons, fixtures, predictions, points and
-- champions stay exactly as they are.
--
-- competition.rename_competition renames exactly one competition: none so
-- named (a fresh database, or already renamed) is a no-op, and more than one
-- stops the migration rather than guess. Admin-only: no client may call it.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function competition.rename_competition(
  p_from text,
  p_to text
) returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_matched integer;
begin
  select count(*) into v_matched
    from competition.competitions
   where name = p_from;
  if v_matched > 1 then
    raise exception
      'rename_competition: % competitions are named "%"; rename by hand',
      v_matched, p_from;
  end if;
  update competition.competitions
     set name = p_to
   where name = p_from;
  return v_matched;
end
$$;

comment on function competition.rename_competition(text, text) is
  'Renames the one competition named p_from to p_to; returns how many were '
  'renamed (0 or 1). More than one match raises instead of guessing '
  '(migration 0099).';

revoke all on function competition.rename_competition(text, text)
  from public, anon, authenticated;

select competition.rename_competition('شهر 9', 'المسابقة الشهرية');

insert into ops.applied_migrations (version)
values ('0099_rename_monthly_competition')
on conflict (version) do nothing;

commit;
