-- The month's turnover check (script 273, 2026-11-14) -- READ ONLY.
--
-- One SELECT and nothing else: it writes nothing and calls only the stable
-- read functions of 0199. Paste it into the Supabase SQL Editor in the last
-- days of a month (from the 25th) and again on the 1st, to see on the live
-- data where the month stands before the jobs close it:
--
--   1 league   the head-to-head month: drawn, rounds approved / locked /
--              void out of 19, the last round, the days left for the rest
--              (rounds never pass the month's end: h2h_rounds_day_in_month),
--              the days ahead with six fixtures or more already known, the
--              admin's settings and excluded days;
--   2 cup      the Elite Cup of the month: qualifiers, stages, titles, and
--              whether it runs into the next month (the next month's rounds
--              then wait for it, decided 2026-11-10);
--   3 close    the month judged (h2h_month_closures, its events) and the
--              next month drawn (h2h_months);
--   4 crown    the monthly contest MM/YYYY: crowned or not, what the
--              automatic crowning waits for (competition.month_crown_state
--              with its own 6 hours), the results to score again, a prize
--              set ahead (the app crowns without one, 2026-11-09);
--   5 results  the month's matches kicked off two hours ago or more with
--              no result: the admin's to enter.
--
-- `params.month` is the month checked (its first day). `params.now_at` is now;
-- a test moves both. Days are Riyadh days, as everywhere in the league.
--
-- Status: 'سليم' fine, 'معلومة' to know, 'تنبيه' to look at, 'توقف' acts
-- before the month ends.
with params as (
  select date '2026-11-01' as month,
         now() as now_at
),
p as (
  select month,
         (month + interval '1 month')::date                  as next_month,
         (month + interval '1 month' - interval '1 day')::date as last_day,
         now_at,
         (now_at at time zone 'Asia/Riyadh')::date          as today
  from params
),
hm as (
  select m.is_pilot, m.seated_count
  from gamification.h2h_months m, p
  where m.month_start = p.month
),
rd as (
  select r.round_no, r.day,
         k.round_id is not null                      as locked,
         coalesce(k.fixture_count, r.fixture_count) as fixtures
  from gamification.h2h_rounds r
  cross join p
  left join gamification.h2h_round_locks k on k.round_id = r.id
  where r.month_start = p.month
),
rs as (
  select count(*)::int                                          as approved,
         (count(*) filter (where locked))::int                  as locked,
         (count(*) filter (where locked and fixtures = 0))::int as void,
         max(round_no)                                          as last_no,
         max(day)                                               as last_day
  from rd
),
fx_days as (
  select (fs.kickoff_at at time zone 'Asia/Riyadh')::date as d,
         count(distinct fs.fixture_id)::int               as n
  from competition.fixture_schedules fs
  cross join p
  where fs.hidden_at is null
    and not fs.is_test
    and exists (select 1 from competition.season_fixtures sf
                where sf.fixture_id = fs.fixture_id)
    and (fs.kickoff_at at time zone 'Asia/Riyadh')::date
        between p.month and p.last_day
  group by 1
),
left_days as (
  select g::date as d
  from p
  cross join rs
  cross join lateral generate_series(
    greatest(p.today, coalesce(rs.last_day + 1, p.month))::timestamp,
    p.last_day::timestamp,
    interval '1 day') g
  where not exists (select 1 from gamification.h2h_day_exclusions x
                    where x.day = g::date)
),
ld as (
  select count(*)::int                                         as days,
         (count(*) filter (where coalesce(f.n, 0) >= 6))::int as known6,
         string_agg(to_char(l.d, 'MM-DD') || ':' || coalesce(f.n, 0),
                    ' ' order by l.d)                          as per_day
  from left_days l
  left join fx_days f on f.d = l.d
),
st as (
  select s.auto_approve, s.auto_approve_lead_hours, s.min_active_days
  from gamification.h2h_settings s
  limit 1
),
ex as (
  select count(*)::int as n,
         string_agg(to_char(x.day, 'MM-DD'), ' ' order by x.day) as days
  from gamification.h2h_day_exclusions x, p
  where x.day between p.month and p.last_day
),
ce as (
  select count(*)::int as n
  from gamification.h2h_cup_entries e, p
  where e.month_start = p.month
),
cs as (
  select s.place, s.stage, s.attempt, s.day,
         l.stage_id is not null as locked
  from gamification.h2h_cup_stages s
  cross join p
  left join gamification.h2h_cup_stage_locks l on l.stage_id = s.id
  where s.month_start = p.month
),
ct as (
  select t.place, t.how, u.display_name
  from gamification.h2h_cup_titles t
  cross join p
  left join identity.users u on u.id = t.champion
  where t.month_start = p.month
),
cup as (
  select (select n from ce)                                        as entries,
         (select count(*)::int from cs)                            as stages,
         (select count(*)::int from ct)                            as titles,
         (select string_agg(place || ' ' || stage || ' ' ||
                            to_char(day, 'MM-DD') ||
                            case when locked then ' مقفلة' else '' end,
                            '، ' order by day) from cs)            as stage_list,
         (select string_agg(place || ': ' ||
                            coalesce(display_name, how), '، '
                            order by place) from ct)               as title_list,
         -- Steps still to play: six (two a path) less the stages already
         -- locked, never below the paths left without a title.
         greatest(6 - (select count(distinct (place, stage))::int
                       from cs where locked),
                  3 - (select count(*)::int from ct))              as steps_left
),
cl as (
  select c.closed_at, c.member_count
  from gamification.h2h_month_closures c, p
  where c.month_start = p.month
),
ev as (
  select count(*)::int as n
  from gamification.events e, p
  where e.event_type = 'h2h_league_finished'
    and e.payload ->> 'month' = p.month::text
),
nx as (
  select m.seated_count
  from gamification.h2h_months m, p
  where m.month_start = p.next_month
),
se as (
  select s.id, s.label, s.end_at
  from competition.seasons s, p
  where s.label = to_char(p.month, 'MM/YYYY')
),
cr as (
  select se.id, se.label,
         (select min(c.crowned_at) from competition.month_champions c
          where c.season_id = se.id)                               as crowned_at,
         (select string_agg(u.display_name, '، ')
          from competition.month_champions c
          join identity.users u on u.id = c.user_id
          where c.season_id = se.id)                               as champions,
         (select mp.prize from competition.month_prizes mp
          where mp.season_id = se.id)                              as prize,
         st.waiting, st.waiting_names, st.skipped, st.skipped_names,
         st.last_result_at, st.rescore
  from se
  cross join p
  cross join lateral competition.month_crown_state(
    se.id, p.now_at, interval '6 hours') st
),
nr as (
  select count(*)::int as n,
         string_agg(m.match, '، ' order by m.kickoff_at) filter (where m.k <= 10)
           as names
  from (
    select fs.home_team || ' × ' || fs.away_team as match, fs.kickoff_at,
           row_number() over (order by fs.kickoff_at, fs.fixture_id) as k
    from se
    cross join p
    join competition.season_fixtures sf on sf.season_id = se.id
    join competition.fixture_schedules fs on fs.fixture_id = sf.fixture_id
    left join scoring.fixture_results r on r.fixture_id = fs.fixture_id
    where fs.hidden_at is null
      and not fs.is_test
      and r.fixture_id is null
      and fs.kickoff_at < se.end_at
      and fs.kickoff_at <= p.now_at - interval '2 hours'
  ) m
),
report (k, section, check_name, value, status) as (
  select 10, '1 دوري المواجهات', 'الشهر مسحوب',
         coalesce((select case when is_pilot then 'تجريبي، ' else '' end
                          || seated_count || ' لاعباً' from hm), 'لا'),
         case when exists (select 1 from hm) then 'سليم' else 'توقف' end
  union all
  select 11, '1 دوري المواجهات', 'الجولات المعتمدة من 19',
         approved || ' (مقفلة ' || locked || '، ملغاة ' || void || ')',
         case when approved >= 19 then 'سليم' else 'معلومة' end
  from rs
  union all
  select 12, '1 دوري المواجهات', 'آخر جولة',
         coalesce(last_no || ' يوم ' || to_char(last_day, 'MM-DD'), 'لا جولة'),
         'معلومة'
  from rs
  union all
  select 13, '1 دوري المواجهات', 'الأيام الباقية للجولات الباقية',
         ld.days || ' يوماً لـ ' || greatest(19 - rs.approved, 0) || ' جولة',
         case when rs.approved >= 19 then 'سليم'
              when 19 - rs.approved > ld.days then 'توقف'
              when 19 - rs.approved = ld.days then 'تنبيه'
              else 'سليم' end
  from rs, ld
  union all
  select 14, '1 دوري المواجهات', 'مباريات الأيام الباقية المعروفة الآن',
         coalesce(ld.per_day, '-') || ' (6 فأكثر: ' || ld.known6 || ' يوماً)',
         'معلومة'
  from ld
  union all
  select 15, '1 دوري المواجهات', 'الإعدادات',
         'اعتماد تلقائي ' || case when auto_approve then 'مفعّل' else 'متوقف' end
         || '، ' || auto_approve_lead_hours || ' ساعة، أيام النشاط '
         || min_active_days,
         case when auto_approve then 'سليم' else 'تنبيه' end
  from st
  union all
  select 16, '1 دوري المواجهات', 'أيام مستبعدة في الشهر',
         case when n = 0 then 'لا' else n || ': ' || days end,
         case when n = 0 then 'سليم' else 'معلومة' end
  from ex
  union all
  select 20, '2 كأس النخبة', 'المتأهلون',
         entries || ' من 12',
         case when entries = 0 and rs.approved < 19 then 'معلومة'
              when entries = 0 then 'تنبيه'
              else 'سليم' end
  from cup, rs
  union all
  select 21, '2 كأس النخبة', 'الأدوار',
         stages || coalesce(' (' || stage_list || ')', ''),
         'معلومة'
  from cup
  union all
  select 22, '2 كأس النخبة', 'الألقاب من 3',
         titles || coalesce(' (' || title_list || ')', ''),
         case when titles >= 3 then 'سليم' else 'معلومة' end
  from cup
  union all
  select 23, '2 كأس النخبة', 'أيام لازمة للدوري والكأس',
         (greatest(19 - rs.approved, 0) + cup.steps_left) || ' يوماً من '
         || ld.days || ' باقية',
         case when cup.titles >= 3 then 'سليم'
              when greatest(19 - rs.approved, 0) + cup.steps_left > ld.days
                then 'معلومة'
              else 'سليم' end
  from rs, ld, cup
  union all
  select 24, '2 كأس النخبة', 'الكأس تمتد إلى الشهر التالي',
         case when cup.titles >= 3 then 'لا، انتهت'
              when greatest(19 - rs.approved, 0) + cup.steps_left > ld.days
                then 'نعم: جولات الشهر التالي تنتظر آخر لقب'
              else 'لا، إن لعبت كل الأيام' end,
         'معلومة'
  from rs, ld, cup
  union all
  select 30, '3 الإغلاق والسحب', 'الشهر محكوم (أُغلق)',
         coalesce((select 'نعم ' || to_char(closed_at at time zone 'Asia/Riyadh',
                                            'MM-DD HH24:MI')
                          || '، ' || member_count || ' لاعباً' from cl), 'لا'),
         'معلومة'
  union all
  select 31, '3 الإغلاق والسحب', 'أحداث نهاية الشهر',
         n::text, 'معلومة'
  from ev
  union all
  select 32, '3 الإغلاق والسحب', 'الشهر التالي مسحوب',
         coalesce((select seated_count || ' لاعباً' from nx), 'لا'),
         case when exists (select 1 from nx) then 'سليم'
              when (select today from p) >= (select next_month from p)
                then 'توقف'
              else 'معلومة' end
  union all
  select 40, '4 تتويج الشهر', 'المسابقة الشهرية',
         coalesce((select string_agg(label, '، ') from se), 'غير موجودة'),
         case when exists (select 1 from se) then 'سليم' else 'توقف' end
  union all
  select 41, '4 تتويج الشهر', 'متوَّج',
         case when crowned_at is null then 'لا'
              else 'نعم ' || to_char(crowned_at at time zone 'Asia/Riyadh',
                                     'MM-DD HH24:MI') || ': ' || champions end,
         case when crowned_at is not null then 'سليم'
              when (select today from p) >= (select next_month from p)
                then 'تنبيه'
              else 'معلومة' end
  from cr
  union all
  select 42, '4 تتويج الشهر', 'مباريات ينتظرها التتويج',
         waiting || coalesce(' (' || waiting_names || ')', ''),
         'معلومة'
  from cr
  union all
  select 43, '4 تتويج الشهر', 'مباريات تُستبعد (بلا نتيجة بعد 6 ساعات)',
         skipped || coalesce(' (' || skipped_names || ')', ''),
         case when skipped = 0 then 'سليم' else 'تنبيه' end
  from cr
  union all
  select 44, '4 تتويج الشهر', 'نتائج تُحتسب من جديد',
         rescore::text,
         case when rescore = 0 then 'سليم' else 'تنبيه' end
  from cr
  union all
  select 45, '4 تتويج الشهر', 'آخر كتابة نتيجة',
         coalesce(to_char(last_result_at at time zone 'Asia/Riyadh',
                          'MM-DD HH24:MI'), '-'),
         'معلومة'
  from cr
  union all
  select 46, '4 تتويج الشهر', 'جائزة محددة مسبقاً',
         coalesce(prize, 'لا'),
         case when prize is null then 'سليم' else 'تنبيه' end
  from cr
  union all
  select 50, '5 النتائج', 'مباريات بدأت قبل ساعتين أو أكثر بلا نتيجة',
         n || coalesce(' (' || names || ')', ''),
         case when n = 0 then 'سليم' else 'تنبيه' end
  from nr
)
select section, check_name, value, status
from report
order by k
