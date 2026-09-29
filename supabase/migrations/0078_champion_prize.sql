-- ============================================================================
-- Migration 0078: the prize of a crowned month
--
-- ADDITIVE / MODIFY-ONLY. One nullable column on competition.month_champions
-- (0077) and the change guard redefined to cover it; no row is inserted,
-- updated or deleted.
--
--   prize   what the champion wins, as the admin typed it at the crowning
--           ("150 ريال سعودي"), shown in the celebration. Optional: a month
--           crowned without one shows no prize line.
--
-- Like the champions and their figures, the prize is part of the record: it
-- is written with the crowning and never changed afterwards. Only the
-- picture may still change.
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table competition.month_champions
  add column if not exists prize text;

alter table competition.month_champions
  drop constraint if exists month_champions_prize_check;
alter table competition.month_champions
  add constraint month_champions_prize_check
    check (prize is null or char_length(btrim(prize)) between 1 and 80);

comment on column competition.month_champions.prize is
  'What the champion wins, as the admin typed it at the crowning (0078). '
  'Null when none was given. Never changed after the crowning.';

-- After the crowning only the picture may change; nothing is deleted. The
-- prize joins the columns that are frozen at the crowning.
create or replace function competition.month_champions_guard_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'month_champions: a crowning is never deleted'
      using errcode = 'check_violation';
  end if;
  if (new.season_id, new.user_id, new.points, new.exact_count,
      new.decided_count, new.referral_points, new.crowned_at,
      new.crowned_by, new.prize)
     is distinct from
     (old.season_id, old.user_id, old.points, old.exact_count,
      old.decided_count, old.referral_points, old.crowned_at,
      old.crowned_by, old.prize) then
    raise exception 'month_champions: only the picture may change'
      using errcode = 'check_violation';
  end if;
  return new;
end
$$;

revoke all on function competition.month_champions_guard_change()
  from public, anon, authenticated;

commit;
