-- End-to-end test for migration 0186: the invitation and duel functions,
-- the users trigger and the invitation views are gone; the stored rows,
-- their tables and their guards stay. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

do $$
declare
  left_over text;
begin
  select string_agg(p.oid::regprocedure::text, ', '
                    order by p.oid::regprocedure::text)
    into left_over
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'gamification' and p.proname ~ 'referral')
      or (n.nspname = 'social' and p.proname ~ 'duel');
  if left_over is distinct from
     'gamification.guard_referral_claim(), gamification.guard_referral_event(), '
     'gamification.reject_referral_mutation(), social.guard_duel_challenge_change()' then
    raise exception 'FAILED: only the four guards may stay, found %', left_over;
  end if;
  raise notice 'ok - only the guards of the stored rows stay';

  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'gamification' and c.relkind = 'v'
                and c.relname ~ 'referral') then
    raise exception 'FAILED: the invitation views must be gone';
  end if;
  raise notice 'ok - the invitation views are gone';

  if exists (select 1 from pg_trigger
              where tgname = 'users_cancel_open_duel_challenges') then
    raise exception 'FAILED: identity.users must not touch the duels any more';
  end if;
  raise notice 'ok - a status change no longer touches the duel tables';

  if to_regclass('gamification.referrals') is null
     or to_regclass('gamification.referral_codes') is null
     or to_regclass('social.duels') is null
     or to_regclass('social.duel_challenges') is null then
    raise exception 'FAILED: the tables and their rows must stay';
  end if;
  raise notice 'ok - the invitation and duel tables stay';

  if not exists (select 1 from ops.applied_migrations
                  where version = '0186_drop_invitation_and_duel_functions') then
    raise exception 'FAILED: 0186 must record itself';
  end if;
  raise notice 'ok - 0186 recorded itself';
end $$;

rollback;
