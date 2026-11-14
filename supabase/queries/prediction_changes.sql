-- A player's prediction writes on a match (script 274, 0211) -- READ ONLY.
--
-- One SELECT, nothing written. Paste it into the Supabase SQL Editor and put
-- part of the player's name and part of a team's name in `params` (Arabic or
-- English, any part). One line a write, oldest first: when (Riyadh), what
-- (أول حفظ / تعديل / حذف), the score and the double before and after, and
-- who wrote it: the app (the player's own save -- only his signed-in account
-- can save his prediction), a merge of two copies of the match, or another
-- statement (shown as it was).
--
-- Writes before 0211 was applied are not in the log; for those the last
-- line shows the prediction as it stands, with its first and last write.
with params as (
  select '%علوش%'  as player,
         '%المغرب%' as team
),
pr as (
  select fp.id, fp.fixture_id, fp.participant_id, fp.home_goals,
         fp.away_goals, fp.is_double, fp.created_at, fp.updated_at,
         u.display_name, fs.home_team, fs.away_team, fs.kickoff_at
  from params pa
  join identity.users u on u.display_name ilike pa.player
  join competition.participants p on p.user_id = u.id
  join prediction.fixture_predictions fp on fp.participant_id = p.id
  join competition.fixture_schedules fs on fs.fixture_id = fp.fixture_id
  where fs.home_team ilike pa.team or fs.away_team ilike pa.team
),
lines as (
  select pr.display_name, pr.home_team, pr.away_team, pr.kickoff_at,
         c.changed_at as at, c.id as seq,
         case c.op when 'insert' then 'أول حفظ'
                   when 'update' then 'تعديل'
                   else 'حذف' end as what,
         c.old_home || '-' || c.old_away ||
           case when c.old_double then ' ×2' else '' end as before,
         c.new_home || '-' || c.new_away ||
           case when c.new_double then ' ×2' else '' end as after,
         case
           when c.source ~* '^\s*(insert\s+into|update)\s+prediction\.fixture_predictions'
             then 'التطبيق (حساب اللاعب)'
           when c.source ~* 'merge' then 'دمج نسخ المباراة'
           else 'أخرى: ' || coalesce(c.source, '-')
         end as who
  from pr
  join prediction.fixture_prediction_changes c on c.prediction_id = pr.id
  union all
  select pr.display_name, pr.home_team, pr.away_team, pr.kickoff_at,
         pr.updated_at, null,
         'الحالي (أول حفظ ' ||
           to_char(pr.created_at at time zone 'Asia/Riyadh', 'MM-DD HH24:MI:SS')
           || ')',
         null,
         pr.home_goals || '-' || pr.away_goals ||
           case when pr.is_double then ' ×2' else '' end,
         'المحفوظ الآن'
  from pr
)
select display_name                                         as "اللاعب",
       home_team || ' × ' || away_team                      as "المباراة",
       to_char(kickoff_at at time zone 'Asia/Riyadh', 'MM-DD HH24:MI') as "الانطلاق",
       to_char(at at time zone 'Asia/Riyadh', 'MM-DD HH24:MI:SS')       as "الوقت",
       what                                                 as "العملية",
       coalesce(before, '-')                                as "قبل",
       coalesce(after, '-')                                 as "بعد",
       round(extract(epoch from kickoff_at - at) / 60)      as "دقائق قبل الانطلاق",
       who                                                  as "من"
from lines
order by kickoff_at desc, home_team, seq nulls last, at
