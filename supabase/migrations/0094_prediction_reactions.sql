-- ============================================================================
-- Migration 0094: reactions on a player's prediction (2026-10-06)
--
-- Phase 1 of the world-class plan, "the features are seen": reactions so far
-- lived only inside a group (social.fixture_reactions), which almost nobody
-- joins. From kickoff every season member sees every prediction on the
-- predictions board; this lets them react to any of them.
--
--   * social.prediction_reactions -- one live reaction per (fixture, the
--     player whose prediction it is, the player reacting). Reacting again
--     changes the reaction; it can be taken back. The kind is the existing
--     closed social.reaction_kind (like, fire, clap, laugh, sad, shock). No
--     points, ever: decided 2026-10-06, points come from predictions only.
--   * notification.notification_kind gains 'prediction_reaction': the owner
--     of the prediction hears of the first reaction each player gives it,
--     in the inbox. Its subject is the fixture and the player who reacted,
--     columns notifications already has (fixture_id 0041, actor_user_id).
--
-- The app checks every rule first (ReactToPrediction). The trigger below is
-- the backstop, for any role including the service role: the reactor and
-- the prediction's owner are both members of the season, they are not the
-- same player, the prediction exists, and the fixture has kicked off.
--
-- fixture_id is opaque, like every season fixture (0019, 0091): no foreign
-- key. Server-only: RLS on, no policy, nothing granted to anon or
-- authenticated.
--
-- ADDITIVE ONLY. Safe to re-run.
-- ============================================================================

begin;

alter type notification.notification_kind
  add value if not exists 'prediction_reaction';

create table if not exists social.prediction_reactions (
  id                    uuid        primary key,
  season_id             uuid        not null
    references competition.seasons (id) on delete restrict,
  fixture_id            uuid        not null,
  target_participant_id uuid        not null
    references competition.participants (id) on delete restrict,
  user_id               uuid        not null
    references identity.users (id) on delete restrict,
  emoji                 social.reaction_kind not null,
  reacted_at            timestamptz not null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint prediction_reactions_one_per_player
    unique (fixture_id, target_participant_id, user_id)
);

comment on table social.prediction_reactions is
  'One live reaction per (fixture, prediction owner, reacting player) on a '
  'prediction revealed after kickoff (0094). Carries no points.';

comment on column social.prediction_reactions.fixture_id is
  'Opaque fixture reference, like competition.season_fixtures.fixture_id '
  '(no foreign key).';

create index if not exists prediction_reactions_season_fixture_idx
  on social.prediction_reactions (season_id, fixture_id);

drop trigger if exists prediction_reactions_set_updated_at
  on social.prediction_reactions;
create trigger prediction_reactions_set_updated_at
  before update on social.prediction_reactions
  for each row
  execute function identity.set_updated_at();

create or replace function social.check_prediction_reaction()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from competition.participants p
     where p.id = new.target_participant_id
       and p.season_id = new.season_id
  ) then
    raise exception 'social.prediction_reaction_target_not_in_season'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from competition.participants p
     where p.id = new.target_participant_id
       and p.user_id = new.user_id
  ) then
    raise exception 'social.prediction_reaction_self'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from competition.participants p
     where p.season_id = new.season_id
       and p.user_id = new.user_id
  ) then
    raise exception 'social.prediction_reaction_not_a_participant'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from prediction.fixture_predictions fp
     where fp.fixture_id = new.fixture_id
       and fp.participant_id = new.target_participant_id
  ) then
    raise exception 'social.prediction_reaction_no_prediction'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from competition.fixture_schedules fs
     where fs.fixture_id = new.fixture_id
       and fs.kickoff_at <= now()
  ) then
    raise exception 'social.prediction_reaction_before_kickoff'
      using errcode = 'check_violation';
  end if;
  return new;
end
$$;

comment on function social.check_prediction_reaction() is
  'Backstop for social.prediction_reactions (0094): both players are season '
  'members, they differ, the prediction exists, the fixture has kicked off.';

drop trigger if exists prediction_reactions_check
  on social.prediction_reactions;
create trigger prediction_reactions_check
  before insert or update on social.prediction_reactions
  for each row
  execute function social.check_prediction_reaction();

alter table social.prediction_reactions enable row level security;
revoke all on social.prediction_reactions from anon, authenticated;

insert into ops.applied_migrations (version)
values ('0094_prediction_reactions')
on conflict (version) do nothing;

commit;
