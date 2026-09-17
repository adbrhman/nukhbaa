-- 0049: index the kickoff range every provider-sync query filters on.
--
-- The sync reads fixtures by kickoff window three times a run (pending
-- results, live scores, duplicate check). Without this index those reads scan
-- competition.fixture_schedules, which grows by every fixture ever played.
--
-- Additive and safe to re-run.

create index if not exists fixture_schedules_kickoff_at_idx
  on competition.fixture_schedules (kickoff_at);
