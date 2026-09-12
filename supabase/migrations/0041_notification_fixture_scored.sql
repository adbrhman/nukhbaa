-- ============================================================================
-- Migration 0041 -- notification.notification_kind gains 'fixture_scored',
-- and notification.notifications gains fixture_id: the deferred storage for
-- NotifyFixtureWinners (Tier-3 exact-score push announcement, wired in the
-- notify_fixture_winners session but left unable to insert/read until now).
--
-- Additive only, forward-only. No existing row is touched: fixture_id is
-- NULL on every pre-existing notification (round_scored / group_member_joined
-- / reaction_received never set it), and the three existing enum values are
-- untouched.
--
-- ALTER TYPE ... ADD VALUE is safe here: the new value is not referenced by
-- any DML in this same file, only by application code that runs afterward
-- (Postgres forbids using a value added by the same transaction, not adding
-- it alongside unrelated DDL).
-- ============================================================================

alter type notification.notification_kind add value if not exists 'fixture_scored';

alter table notification.notifications
  add column if not exists fixture_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'notifications_fixture_id_fkey'
  ) then
    alter table notification.notifications
      add constraint notifications_fixture_id_fkey
      foreign key (fixture_id)
      references competition.fixture_schedules (fixture_id)
      on delete cascade;
  end if;
end
$$;

comment on column notification.notifications.fixture_id is
  'Referenced fixture (fixture_scored). The link is FROM notification TO '
  'competition -- no notification reference is ever added to a fixture row '
  '(mirrors round_id/group_id). NULL for every other kind.';
