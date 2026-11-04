-- ============================================================================
-- Migration 0200: the sports publisher (scripts 207-208)
--
-- ADDITIVE ONLY. A new schema `publisher` with six tables and one public
-- Storage bucket. No row of any existing table is changed or removed, and
-- no existing table gains a column or a reference: the publisher reads the
-- schedule and the results, and writes only here.
--
-- Decided by the owner on 2026-11-04: goals and final results of the
-- matches an admin picks are posted to Facebook and Instagram by the
-- server, and prepared for X, where an admin shares them by hand; each
-- club is drawn as a disc of its colour with its name, never its crest.
--
-- Tables (backend-only: RLS on, nothing granted to anon or authenticated)
--   publisher.settings     one row per platform: on/off, which goals, the
--                          final result, the hold, the least gap, the cap
--   publisher.coverage     the matches an admin picked, with the score the
--                          publisher last read; stopping keeps the row
--   publisher.goals        every goal it saw: pending, confirmed, withdrawn
--   publisher.posts        one row per post and platform; `dedupe_key` is
--                          unique, so a goal is never queued twice
--   publisher.club_badges  a club's colour and label for its disc
--   publisher.post_metrics the reach and reactions read back from a post
--
-- Storage
--   publisher-cards        public (Instagram fetches the picture by URL);
--                          JPEG only, 2 MB at most
--
-- Apply BEFORE deploying the server. Safe to re-run.
-- ============================================================================

begin;

create schema if not exists publisher;

create table if not exists publisher.settings (
  platform        text        primary key,
  enabled         boolean     not null default false,
  goals           text        not null default 'all',
  final_result    boolean     not null default true,
  hold_seconds    integer     not null,
  min_gap_seconds integer     not null default 0,
  daily_cap       integer     not null,
  updated_at      timestamptz not null default now(),
  updated_by      uuid,
  constraint settings_platform check (platform in ('facebook', 'instagram', 'x')),
  constraint settings_goals check (goals in ('all', 'key', 'none')),
  constraint settings_hold check (hold_seconds between 60 and 1800),
  constraint settings_gap check (min_gap_seconds between 0 and 3600),
  constraint settings_cap check (daily_cap between 0 and 50)
);

create table if not exists publisher.coverage (
  fixture_id     uuid        primary key,
  added_by       uuid,
  added_at       timestamptz not null default now(),
  stopped_at     timestamptz,
  known_home     integer     not null default 0,
  known_away     integer     not null default 0,
  known_at       timestamptz,
  final_queued_at timestamptz,
  constraint coverage_known check (known_home >= 0 and known_away >= 0)
);

create table if not exists publisher.goals (
  id             uuid        primary key default gen_random_uuid(),
  fixture_id     uuid        not null,
  goal_key       text        not null,
  home           boolean     not null,
  before_home    integer     not null,
  before_away    integer     not null,
  state          text        not null default 'pending',
  first_seen_at  timestamptz not null,
  feed_minute    integer,
  confirmed_at   timestamptz,
  withdrawn_at   timestamptz,
  moment         text,
  scorer         text,
  minute_label   text,
  penalty        boolean     not null default false,
  own_goal       boolean     not null default false,
  details_tries  integer     not null default 0,
  card_path      text,
  constraint goals_key check (goal_key ~ '^[ha][1-9][0-9]?$'),
  constraint goals_state check (state in ('pending', 'confirmed', 'withdrawn')),
  constraint goals_before check (before_home >= 0 and before_away >= 0)
);

-- A goal the VAR took back leaves its key free for the next goal of that
-- side; two live goals never share one.
create unique index if not exists goals_live_key
  on publisher.goals (fixture_id, goal_key)
  where state <> 'withdrawn';
create index if not exists goals_fixture on publisher.goals (fixture_id);

create table if not exists publisher.posts (
  id              uuid        primary key default gen_random_uuid(),
  dedupe_key      text        not null unique,
  fixture_id      uuid        not null,
  goal_id         uuid        references publisher.goals (id),
  kind            text        not null,
  platform        text        not null,
  state           text        not null,
  body            text        not null,
  card_path       text,
  riyadh_day      date        not null,
  not_before      timestamptz not null,
  next_attempt_at timestamptz,
  claimed_until   timestamptz,
  attempts        integer     not null default 0,
  external_id     text,
  error           text,
  created_at      timestamptz not null default now(),
  published_at    timestamptz,
  updated_at      timestamptz not null default now(),
  constraint posts_kind check (kind in ('goal', 'final', 'correction')),
  constraint posts_platform check (platform in ('facebook', 'instagram', 'x')),
  constraint posts_state check (state in (
    'queued', 'published', 'dry_run', 'ready_to_share', 'shared',
    'failed', 'uncertain', 'skipped', 'cancelled')),
  constraint posts_body check (char_length(body) between 1 and 2200),
  constraint posts_attempts check (attempts >= 0)
);

create index if not exists posts_due
  on publisher.posts (not_before)
  where state = 'queued';
create index if not exists posts_created on publisher.posts (created_at desc);
create index if not exists posts_day
  on publisher.posts (platform, riyadh_day)
  where kind = 'goal';

create table if not exists publisher.club_badges (
  team_id    uuid        primary key,
  fill       text        not null,
  label      text,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  constraint club_badges_fill check (fill ~ '^#[0-9A-Fa-f]{6}$'),
  constraint club_badges_label check (
    label is null or char_length(btrim(label)) between 1 and 24)
);

create table if not exists publisher.post_metrics (
  post_id   uuid        primary key references publisher.posts (id),
  read_at   timestamptz not null,
  reach     integer,
  reactions integer,
  comments  integer,
  shares    integer,
  raw       jsonb       not null default '{}'::jsonb
);

comment on schema publisher is
  'The sports publisher (0200): goals and final results of the matches an '
  'admin picks, posted to Facebook and Instagram, prepared for X. Reads the '
  'schedule and the results; writes only here.';
comment on table publisher.posts is
  'One row per post and platform (0200). dedupe_key is unique: goal:<goal '
  'id>:<platform>, final:<fixture id>:<platform>, correction:<goal '
  'id>:<platform>. A row is never deleted; its state records its fate.';

alter table publisher.settings enable row level security;
alter table publisher.coverage enable row level security;
alter table publisher.goals enable row level security;
alter table publisher.posts enable row level security;
alter table publisher.club_badges enable row level security;
alter table publisher.post_metrics enable row level security;
revoke all on all tables in schema publisher from anon, authenticated;
revoke all on schema publisher from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('publisher-cards', 'publisher-cards', true, 2097152,
        array['image/jpeg'])
on conflict (id) do nothing;

insert into ops.applied_migrations (version)
values ('0200_publisher')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0200_publisher';                               -- 1 row
-- select id, public from storage.buckets where id = 'publisher-cards';
-- select count(*) from publisher.posts;                             -- 0
