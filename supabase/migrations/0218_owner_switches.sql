-- ============================================================================
-- Migration 0218: the owner's switches, first the month's crowning
--
-- ADDITIVE ONLY. One new table with one row, and one check constraint
-- widened by one value; no other row is written, changed or removed.
--
-- Decided by the owner on 2026-11-19 and 2026-11-20 (decision Q04, script
-- 286): the crowning has a stop in the owners' hands. While it is off, no
-- month is crowned by itself and no admin crowns one by hand; only an owner
-- may crown by hand. The server reads the switch on every run, never once
-- at boot.
--
-- 1. ops.owner_switches: one row per switch, on by default. Only
--    'crowning' for now; the other switches come with their own batches.
-- 2. competition.month_crown_notices: the kind 'held', the owners told once
--    that a month waits for its crowning because the switch is off.
--
-- No client role reads the switches: the server alone does. Until the
-- owner's page has its button, supabase/queries/crowning_pause.sql and
-- crowning_resume.sql turn it off and on.
--
-- Safe to re-run.
-- ============================================================================

begin;

create table if not exists ops.owner_switches (
  switch_key text        primary key,
  is_on      boolean     not null default true,
  reason     text,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  constraint owner_switches_key_check
    check (switch_key in ('crowning')),
  constraint owner_switches_reason_not_blank
    check (reason is null or length(btrim(reason)) > 0),
  constraint owner_switches_changed_by_fkey
    foreign key (changed_by) references identity.users (id)
    on delete restrict
);

comment on table ops.owner_switches is
  'The owners'' switches (script 286, decision Q04): on by default; the '
  'server reads each one on every run. crowning: off holds every month''s '
  'crowning, automatic or by an admin''s hand; an owner may still crown.';

insert into ops.owner_switches (switch_key, is_on)
values ('crowning', true)
on conflict (switch_key) do nothing;

alter table ops.owner_switches enable row level security;
revoke all on ops.owner_switches from anon, authenticated;

alter table competition.month_crown_notices
  drop constraint if exists month_crown_notices_kind_check;
alter table competition.month_crown_notices
  add constraint month_crown_notices_kind_check
  check (kind in ('crowned', 'tie', 'changed', 'empty', 'held'));

insert into ops.applied_migrations (version)
values ('0218_owner_switches')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0218_owner_switches';               -- one row
-- select switch_key, is_on from ops.owner_switches;     -- crowning | true
