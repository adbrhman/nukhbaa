-- ============================================================================
-- Migration 0186: the invitation and duel functions and views are dropped
-- (script 154, 2026-10-26)
--
-- DROPS FUNCTIONS, ONE TRIGGER AND VIEWS ONLY. No table, column, index or
-- row is removed or changed: every invitation, invitation point, duel and
-- duel notification stays stored exactly as it was (protocol section 5).
--
-- Why: the owner removed the invitations and the duels from every layer
-- (script 153). Since that server is live nothing calls these server-only
-- functions or reads these views; the boards stopped reading invitation
-- points in 0185. What is dropped:
--
-- * gamification: ensure_referral_code, mark_referral_install,
--   claim_referral, qualify_referrals, expire_idle_referrals,
--   review_referral, referral_hash, and the views referral_invitations,
--   referral_season_points, referral_month_points.
-- * social: create_duel_challenge, accept_duel_challenge,
--   cancel_duel_challenge, decline_duel_challenge, new_duel_code, and the
--   trigger users_cancel_open_duel_challenges on identity.users with its
--   function, which touched the duel tables on every status change.
--
-- Kept on purpose: the stored rows' own guards (reject_referral_mutation,
-- guard_referral_claim, guard_referral_event, guard_duel_challenge_change)
-- so the kept history cannot be altered, gamification.normalized_email
-- (an index on identity.users uses it), and the `referrals` switch row.
--
-- Apply AFTER the server of script 153 is live: the server before it calls
-- these functions and reads these views. A `drop view` fails if anything
-- still depends on the view, so a missed reader stops the migration
-- instead of breaking it.
--
-- Safe to re-run.
-- ============================================================================

begin;

drop view if exists gamification.referral_invitations;
drop view if exists gamification.referral_season_points;
drop view if exists gamification.referral_month_points;

drop function if exists gamification.qualify_referrals(timestamptz);
drop function if exists gamification.expire_idle_referrals(timestamptz);
drop function if exists gamification.review_referral(uuid, text, uuid, text, timestamptz);
drop function if exists gamification.claim_referral(uuid, text, text, text, timestamptz);
drop function if exists gamification.mark_referral_install(uuid, text, timestamptz);
drop function if exists gamification.ensure_referral_code(uuid);
drop function if exists gamification.referral_hash(text, text);

drop trigger if exists users_cancel_open_duel_challenges on identity.users;
drop function if exists social.cancel_open_duel_challenges_for_user();
drop function if exists social.create_duel_challenge(uuid, uuid, uuid, integer, uuid, timestamptz);
drop function if exists social.accept_duel_challenge(uuid, uuid, timestamptz);
drop function if exists social.cancel_duel_challenge(uuid, uuid);
drop function if exists social.decline_duel_challenge(uuid, uuid);
drop function if exists social.new_duel_code();

insert into ops.applied_migrations (version)
values ('0186_drop_invitation_and_duel_functions')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0186_drop_invitation_and_duel_functions';             -- 1 row
-- select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where (n.nspname = 'gamification' and p.proname ~ 'referral')
--     or (n.nspname = 'social' and p.proname ~ 'duel');                    -- 4 (the guards)
-- select count(*) from gamification.referrals;                             -- unchanged
-- select count(*) from social.duels;                                       -- unchanged
