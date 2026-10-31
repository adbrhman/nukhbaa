-- Preview of the elite draw (NK182, decided 2026-10-31) -- READ ONLY.
--
-- One SELECT and nothing else: it writes nothing. Paste it into the
-- Supabase SQL Editor before the draw to see, on the live data, exactly
-- whom DrawH2hMonth will seat and where.
--
-- `params.month` is the month whose predictions are read: the month BEFORE
-- the one drawn (2026-10-01 for the November draw).
--
-- The facts are those of PostgresH2hDrawSource.activeOrderSql, column for
-- column:
--   fixtures   the month's visible, non-test fixtures of the player's seasons
--   predicted  how many of them the player predicted
--   missed     fixtures - predicted (the commitment: fewer is better)
--   days       Riyadh days with at least one prediction (min_active_days,
--              5 unless an admin changed it, to enter the draw)
--   points     stored fixture scores of the month, the double included
--   exact      exact scorelines
-- ordered exactly like it: missed ASC, points DESC, exact DESC, user id.
-- The order is then dealt as H2hLeaguePolicy.eliteDraw deals it: the first
-- 80 like a snake into groups 1..4 (1 2 3 4, 4 3 2 1, ...), the rest twenty
-- at a time into groups 5, 6, ...; a single player left at the end joins
-- the group before him.
--
-- One row per player of the month: place in the order, group, name, the
-- six facts, eligible (false: too few days, not drawn), and per group its
-- size and the sums of its points and misses -- the four elite groups
-- should be close to one another.
-- Suspended and deleted accounts are left out, as in the draw.
with params as (
  select date '2026-10-01' as month
),
settings as (
  select coalesce(
           (select min_active_days from gamification.h2h_settings limit 1),
           5) as min_days
),
fx as (
  select distinct sf.season_id, fs.fixture_id,
         (fs.kickoff_at at time zone 'Asia/Riyadh')::date as d
  from competition.season_fixtures sf
  join competition.fixture_schedules fs on fs.fixture_id = sf.fixture_id
  cross join params pr
  where fs.hidden_at is null
    and not fs.is_test
    and (fs.kickoff_at at time zone 'Asia/Riyadh')::date >= pr.month
    and (fs.kickoff_at at time zone 'Asia/Riyadh')::date
        < (pr.month + interval '1 month')::date
),
per as (
  select p.user_id,
         count(distinct fx.fixture_id)                                  as fixtures,
         count(distinct fx.fixture_id) filter (where fp.id is not null) as predicted,
         count(distinct fx.d) filter (where fp.id is not null)          as days,
         count(distinct fx.fixture_id)
           - count(distinct fx.fixture_id) filter (where fp.id is not null)
                                                                        as missed,
         coalesce(sum(s.points), 0)                                     as points,
         count(*) filter (where s.grade = 'exact_scoreline')            as exact
  from competition.participants p
  join identity.users u on u.id = p.user_id and u.status <> 'suspended'
  join fx on fx.season_id = p.season_id
  left join prediction.fixture_predictions fp
    on fp.fixture_id = fx.fixture_id and fp.participant_id = p.id
  left join scoring.fixture_scores s
    on s.fixture_id = fx.fixture_id and s.participant_id = p.id
  group by p.user_id
),
ordered as (
  select per.*,
         per.days >= st.min_days as eligible,
         (row_number() over (
            partition by per.days >= st.min_days
            order by per.missed asc, per.points desc, per.exact desc,
                     per.user_id)) - 1 as pos
  from per cross join settings st
),
sizes as (
  select count(*) filter (where eligible)            as n,
         least(count(*) filter (where eligible), 80) as elite_n
  from ordered
),
dealt as (
  select o.*,
         case
           when not o.eligible then null
           when o.pos < sz.elite_n then
             1 + case
                   when (o.pos / g.k) % 2 = 0 then o.pos % g.k
                   else g.k - 1 - o.pos % g.k
                 end
           when (sz.n - sz.elite_n) % 20 = 1
                and sz.n - sz.elite_n > 1
                and o.pos = sz.n - 1 then
             -- the single last player joins the group before him
             4 + (o.pos - sz.elite_n) / 20
           else 5 + (o.pos - sz.elite_n) / 20
         end as grp
  from ordered o
  cross join sizes sz
  cross join lateral (
    select greatest(1, least(4, sz.elite_n / 2)) as k
  ) g
)
select case when d.eligible then d.pos + 1 end                      as place,
       d.grp                                                        as "group",
       coalesce(u.display_name, '(no name)')                        as name,
       d.fixtures, d.predicted, d.missed, d.days, d.points, d.exact,
       d.eligible,
       count(*) over (partition by d.grp)                           as group_size,
       sum(d.points) over (partition by d.grp)                      as group_points,
       sum(d.missed) over (partition by d.grp)                      as group_missed,
       d.user_id
from dealt d
join identity.users u on u.id = d.user_id
order by d.eligible desc, d.pos;
