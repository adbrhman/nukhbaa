-- Migration 0092 - duel notifications: a privately challenged player is
-- told, and so is a challenger whose challenge was accepted.
--
-- ADDITIVE ONLY. No row is touched.
--   * notification.notification_kind gains 'duel_challenged' and
--     'duel_accepted';
--   * notification.notifications gains duel_challenge_id (NULL for every
--     other kind), the challenge the notification is about;
--   * notification.push_opens accepts the push link 'duel'. Its check is
--     replaced by the same list plus that one value.
--
-- ALTER TYPE ... ADD VALUE is safe in this transaction: nothing below uses
-- the new values; only application code that runs afterward does.
--
-- Safe to re-run.

begin;

alter type notification.notification_kind add value if not exists 'duel_challenged';
alter type notification.notification_kind add value if not exists 'duel_accepted';

alter table notification.notifications
  add column if not exists duel_challenge_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'notifications_duel_challenge_id_fkey'
  ) then
    alter table notification.notifications
      add constraint notifications_duel_challenge_id_fkey
      foreign key (duel_challenge_id)
      references social.duel_challenges (id)
      on delete cascade;
  end if;
end
$$;

comment on column notification.notifications.duel_challenge_id is
  'Referenced duel challenge (duel_challenged / duel_accepted, 0092). The '
  'link is FROM notification TO the challenge; NULL for every other kind.';

alter table notification.push_opens
  drop constraint if exists push_opens_link_check;
alter table notification.push_opens
  add constraint push_opens_link_check
    check (link in ('fixtures', 'league', 'inbox', 'duel'));

insert into ops.applied_migrations (version)
values ('0092_duel_notifications')
on conflict (version) do nothing;

commit;
