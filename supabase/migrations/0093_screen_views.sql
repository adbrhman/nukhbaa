-- ============================================================================
-- Migration 0093: which screens each player opens, per Riyadh day (2026-10-06)
--
-- Phase 0 of the world-class plan: the display features (badges, insights,
-- the elite card, groups, duels) have no baseline without knowing who opens
-- them. One table and one view:
--
--   * gamification.screen_views -- one row per (Riyadh day, screen, player)
--     with how many times that player opened that screen that day. The app
--     counts opens in memory and sends them in one POST /me/screen-views when
--     it goes to the background; the server adds them here. A day-level row
--     keeps the table small on the free plan (one row per screen a player
--     actually opened, never one row per tap).
--   * gamification.kpi_screen_usage_weekly -- per Riyadh week (Monday) and
--     screen: how many players opened it, how many opens, and the share of
--     that week's active players (gamification.user_active_days, 0069).
--
-- The screen names are a closed vocabulary owned by the domain
-- (ScreenName); the check below only guards their shape. No content, no
-- device identifiers, nothing about what was on the screen.
--
-- Server-only, as 0069 did for notification.push_opens: RLS on, no policy,
-- nothing granted to anon or authenticated. Rows go with their user.
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

create table if not exists gamification.screen_views (
  view_date  date        not null,
  screen     text        not null,
  user_id    uuid        not null
    references identity.users (id) on delete cascade,
  opens      integer     not null,
  first_at   timestamptz not null default now(),
  last_at    timestamptz not null default now(),
  constraint screen_views_pkey primary key (view_date, screen, user_id),
  constraint screen_views_screen_check
    check (screen ~ '^[a-z][a-z0-9_]{1,39}$'),
  constraint screen_views_opens_check
    check (opens between 1 and 100000)
);

comment on table gamification.screen_views is
  'Screen opens per (Riyadh day, screen, player), summed from the reports '
  'the app sends to POST /me/screen-views (0093). Read by '
  'gamification.kpi_screen_usage_weekly.';

create index if not exists screen_views_user_idx
  on gamification.screen_views (user_id, view_date);

alter table gamification.screen_views enable row level security;
revoke all on gamification.screen_views from anon, authenticated;

create or replace view gamification.kpi_screen_usage_weekly as
with views as (
  select
    (v.view_date - (extract(isodow from v.view_date)::int - 1))
      as week_start,
    v.screen,
    v.user_id,
    sum(v.opens) as opens
  from gamification.screen_views v
  group by 1, 2, 3
),
active as (
  select
    (a.activity_date - (extract(isodow from a.activity_date)::int - 1))
      as week_start,
    count(distinct a.user_id) as active_players
  from gamification.user_active_days a
  group by 1
)
select
  w.week_start,
  w.screen,
  count(*) as players,
  sum(w.opens)::bigint as opens,
  coalesce(ac.active_players, 0) as active_players,
  round(count(*)::numeric / nullif(ac.active_players, 0), 4)
    as share_of_active
from views w
left join active ac on ac.week_start = w.week_start
group by w.week_start, w.screen, ac.active_players;

comment on view gamification.kpi_screen_usage_weekly is
  'Per Riyadh week and screen: players who opened it, total opens, and the '
  'share of that week''s active players (0093).';

revoke all on gamification.kpi_screen_usage_weekly from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0093_screen_views')
on conflict (version) do nothing;

commit;
