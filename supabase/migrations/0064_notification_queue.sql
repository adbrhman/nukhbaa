-- ============================================================================
-- Migration 0064: the deferred-push queue (P3-2)
--
-- Quiet hours (P3-2a) are 23:00 to 08:00 on the reader's own clock. The daily
-- reminder simply skips them -- a reminder after the quiet hours would arrive
-- after the kickoff it was about. Every other push (a scored exact result,
-- an admin announcement) is still worth reading in the morning, so instead of
-- being sent into the night it waits here until deliver_after.
--
-- ## A row is one push for one user, not one per device
-- Tokens are read at delivery time from notification.device_tokens, so a
-- phone registered or retired overnight is honoured, and a user who removed
-- every device by morning gets nothing.
--
-- ## At most once
-- The flush job claims due rows by setting sent_at in the same statement that
-- reads them (FOR UPDATE SKIP LOCKED), then sends. A crash between the claim
-- and the send loses that push; it never sends it twice. A late-night
-- notification delivered twice is worse than one that is lost.
--
-- ## Append-only, except for the claim
-- DELETE is refused for every role, and UPDATE is refused unless it only sets
-- a NULL sent_at. The queue is therefore also the record of what was deferred
-- and when it went out.
--
-- Server-only: RLS on, no policy and no grant for anon or authenticated.
-- Nothing writes here until P3-2c routes the notifiers through it; until
-- then the flush job finds nothing and does nothing.
--
-- ADDITIVE ONLY. One table, no data written. Safe to re-run.
-- ============================================================================

begin;

create table if not exists notification.notification_queue (
  id            uuid        primary key,
  user_id       uuid        not null,
  title         text        not null,
  body          text        not null,
  deliver_after timestamptz not null,
  enqueued_at   timestamptz not null default now(),
  sent_at       timestamptz,
  constraint notification_queue_user_id_fkey foreign key (user_id)
    references identity.users (id) on delete cascade,
  constraint notification_queue_title_nonblank check (btrim(title) <> ''),
  constraint notification_queue_body_nonblank check (btrim(body) <> '')
);

comment on table notification.notification_queue is
  'Pushes deferred out of a user''s quiet hours (P3-2). One row per push per '
  'user; tokens are read when it is delivered. sent_at is set once, by the '
  'claim that delivers it. Append-only otherwise; server-only.';

comment on column notification.notification_queue.deliver_after is
  'The end of the quiet hours on the user''s clock when the push was queued '
  '(08:00 local), as a UTC instant.';

comment on column notification.notification_queue.sent_at is
  'When the flush job claimed the row for delivery. NULL while waiting.';

-- The flush job's only read: waiting rows in delivery order.
create index if not exists notification_queue_waiting_idx
  on notification.notification_queue (deliver_after, id)
  where sent_at is null;

create or replace function notification.reject_notification_queue_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception
      'notification.notification_queue is append-only: DELETE is forbidden'
      using errcode = 'check_violation';
  end if;
  if old.sent_at is not null
     or new.sent_at is null
     or new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.title is distinct from old.title
     or new.body is distinct from old.body
     or new.deliver_after is distinct from old.deliver_after
     or new.enqueued_at is distinct from old.enqueued_at then
    raise exception
      'notification.notification_queue: an UPDATE may only set a NULL sent_at'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

comment on function notification.reject_notification_queue_mutation() is
  'Backstop for notification.notification_queue: no DELETE, and an UPDATE '
  'only claims a waiting row by setting its sent_at, for every role '
  'including the service role that bypasses RLS.';

drop trigger if exists notification_queue_reject_mutation
  on notification.notification_queue;
create trigger notification_queue_reject_mutation
  before update or delete on notification.notification_queue
  for each row
  execute function notification.reject_notification_queue_mutation();

alter table notification.notification_queue enable row level security;

revoke all on notification.notification_queue from anon, authenticated;

commit;

-- Verification (read-only):
-- select count(*) from notification.notification_queue;          -- 0
-- select relrowsecurity from pg_class
--  where oid = 'notification.notification_queue'::regclass;      -- t
