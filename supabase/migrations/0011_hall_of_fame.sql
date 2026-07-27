-- Migration 0011 — Hall of Fame: the platform-wide, ALL-TIME standings as a
-- READ-SIDE PROJECTION over the SAME ratified append-only ledger the season
-- board already reads (Axiom 5: no new points source, no second source of
-- truth). This migration adds ONLY a projection VIEW — deliberately NO new
-- writable table (mirrors migration 0006's Leaderboards discipline exactly,
-- just aggregated by user across every season instead of scoped to one).
--
-- ADRs / Axioms enforced PHYSICALLY / honoured by this migration:
--
--   * Axiom 5 (single protected truth for points): a user's Hall of Fame total
--     is the signed SUM of `ledger.point_entries.amount` across every
--     participant row that user has ever held (one per season they joined),
--     so the board can never disagree with the sum of that user's own
--     per-season balances. No stored/materialized ranking table — standings
--     are aggregated on read. Ranks are NOT computed here: the VIEW supplies
--     per-user TOTALS only; the pure domain `HallOfFame.rank` assigns the
--     ordering + standard-competition ("1224") ranks, identically to how
--     `SeasonLeaderboard.rank` does for the season board.
--
--   * Cross-season aggregation, keyed by user not participant: a user holds a
--     DIFFERENT `competition.participants` row per season (Database ADR §1 —
--     Participant is keyed on the season), so this view groups by
--     `p.user_id` (constant across seasons) rather than `p.id`, and also
--     counts `count(distinct p.season_id)` as `seasons_played`.
--
--   * Completeness: only users who hold at least one participant row appear —
--     a user who has never joined any season contributes no row (there is
--     nothing to aggregate), which is a legitimate absence, not an error; the
--     application-layer use-case pages this list, so an empty platform (no
--     one has ever played) legitimately yields an empty board.
--
--   * Security ADR §2 / Database ADR §10: unlike the season board (member-only
--     visibility), the Hall of Fame is intentionally PUBLIC to any
--     authenticated user (`GetHallOfFame` requires only `PlatformRole.user`,
--     no membership gate) — a Hall of Fame is meant to be seen by everyone.
--     The VIEW itself still inherits the base tables' RLS under
--     `security_invoker` as the backstop (Axiom 6) for any direct client
--     select; the backend service role bypasses RLS and reads the whole
--     board, same as 0006.
--
-- Forward-only, expand-only (Platform ADR). Safe to re-run: every statement is
-- guarded. Reuses the tables from migrations 0002/0005; introduces no new
-- writable table, enum, trigger, or points source.

-- ---------------------------------------------------------------------------
-- hall_of_fame_standings — the platform-wide, all-time projection VIEW.
--
-- One row per user who holds at least one `competition.participants` row.
-- Columns match exactly what
-- `PostgresLeaderboardRepository.allTimeStandings` selects:
--   user_id         — the platform identity the entry is keyed on (constant
--                     across every season that user has joined).
--   total_points    — signed SUM(amount) of every ledger entry across every
--                     participant row this user has ever held (corrections
--                     already netted — Axiom 5); 0 for a user enrolled in at
--                     least one season but never credited.
--   seasons_played  — count of DISTINCT seasons this user has participated
--                     in (audit/traceability — mirrors entry_count on the
--                     season board, but at season granularity).
--
-- Anchored on `competition.participants` (so every user who has ever joined
-- any season appears) LEFT-joined to the ledger (so a never-credited user
-- still appears with a zero total). NO ORDER BY: ordering + ranks are the
-- domain's job (`HallOfFame.rank`), realized in exactly one place.
-- ---------------------------------------------------------------------------
create or replace view leaderboard.hall_of_fame_standings as
  select
    p.user_id                            as user_id,
    coalesce(sum(e.amount), 0)::bigint   as total_points,
    count(distinct p.season_id)::bigint  as seasons_played
  from competition.participants p
  left join ledger.point_entries e
    on e.participant_id = p.id
  group by p.user_id;

comment on view leaderboard.hall_of_fame_standings is
  'All-time, cross-season standings projection (Axiom 5: a read-side '
  'projection over the append-only ledger, never a second points source). '
  'One row per user with at least one participant row across any season; '
  'total_points = signed SUM(amount) across every participant row that user '
  'has ever held; seasons_played = count of distinct seasons. Ranks are '
  'assigned by the pure domain HallOfFame.rank, NOT stored here.';

-- ---------------------------------------------------------------------------
-- Row-Level Security. Mirrors 0006: security_invoker so a client selecting the
-- VIEW directly inherits the base tables' self-read RLS (never another user's
-- total via direct select — no enumeration oracle); the backend service role
-- bypasses RLS. The application's authorization gate (`GetHallOfFame` requires
-- only an authenticated `PlatformRole.user` — intentionally public, unlike the
-- season board) is the primary control for the backend-served endpoint; this
-- is the backstop (Axiom 6) for any other access path.
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    execute
      'alter view leaderboard.hall_of_fame_standings set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.hall_of_fame_standings from anon;
grant select on leaderboard.hall_of_fame_standings to authenticated;
