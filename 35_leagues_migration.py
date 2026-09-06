#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""35_leagues_migration — دفعة 1/4: جدول الدوريات وربط المباراة به."""
import os, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
MIG = os.path.join(ROOT, "supabase/migrations")
assert os.path.isdir(MIG), "migrations dir not found under %s" % ROOT

TARGET = os.path.join(MIG, "0027_fixture_league.sql")
assert not os.path.exists(TARGET), "0027 already exists — check numbering"
assert os.path.exists(os.path.join(MIG, "0026_team_logos_storage_bucket.sql")), \
    "0026 missing — unexpected migration state"

SQL = r'''-- ============================================================================
-- Migration 0027: fixture_league
--
-- Gives a fixture the one thing its card cannot currently show: which
-- football competition it was actually played in ("Premier League",
-- "LaLiga"). Today the matches card falls back to the *contest's* name —
-- "شهر 9" — because that is the only name in reach, and the reference
-- design shows the league instead.
--
-- ## This un-defers ADR-003 §2.2's `tournament` (see 0013's header)
-- Migration 0013 deliberately shipped Football Data WITHOUT `tournament` /
-- `tournament_edition`, on the reasoning that "nothing in the current v1 UI
-- consumes tournament-level metadata" and that adding it would be dead
-- schema — with an explicit "revisit if/when actually needed". It is needed
-- now, and only in its thinnest possible form: an identity row (name +
-- logo), no edition/season shape, no provider reference. Named `leagues`
-- rather than `tournaments` because that is the word the product and the
-- admin UI already use.
--
-- ## Why NOT `competition.competitions`
-- Eight league-named rows already sit in `competition.competitions`
-- (الدوري الإنجليزي الممتاز, LaLiga, …), left over from the pre-monthly
-- model, and pointing a fixture at one of them would be the cheaper edit.
-- It is also wrong: `competition.competitions` now means "a contest users
-- join and score points in" — it holds "شهر 9" too — so a fixture's
-- `league_id` could point at a monthly contest and the type would allow it.
-- A league is football reality, not contest structure; it belongs in
-- `football_data`, beside `teams`.
--
-- ## Additive/expand-only
-- `league_id` is nullable with `on delete set null`: every one of the 21
-- fixtures already stored stays valid and unchanged, and a client that does
-- not send a league keeps working. Backfilling the existing rows and the
-- admin picker are separate batches — this migration adds capacity only and
-- changes no behaviour on its own.
--
-- Axiom 3 is intact: `football_data.fixtures` still carries no competition
-- reference. The column added here is on `competition.fixture_schedules`
-- (the admin-fed schedule row) and points into `football_data`, not into
-- `competition.competitions` / `competition.rounds` — it says which league
-- the match belongs to, never which contest owns it.
-- ============================================================================

-- ---------------------------------------------------------------------
-- leagues — slowly-changing reference identity, same shape and the same
-- public-crest story as football_data.teams (migrations 0013 + 0026), so
-- `logo_url` can point at the existing `team-logos` bucket or any CDN
-- without a second asset pipeline.
-- ---------------------------------------------------------------------
create table if not exists football_data.leagues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  short_name  text,
  logo_url    text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint leagues_name_not_blank check (btrim(name) <> '')
);

comment on table football_data.leagues is
  'Football Data-owned. The thin form of ADR-003 §2.2''s deferred '
  '`tournament`: a league''s display identity (name + logo) and nothing '
  'else — no edition/season shape, no provider reference (provenance '
  'belongs in external_identity_map, as for teams). Referenced by '
  'competition.fixture_schedules.league_id (migration 0027).';

drop trigger if exists leagues_set_updated_at on football_data.leagues;
create trigger leagues_set_updated_at
  before update on football_data.leagues
  for each row
  execute function identity.set_updated_at();

alter table football_data.leagues enable row level security;

drop policy if exists leagues_select_authenticated on football_data.leagues;
create policy leagues_select_authenticated
  on football_data.leagues
  for select
  to authenticated
  using (true);

-- ---------------------------------------------------------------------
-- fixture_schedules.league_id — nullable enrichment, mirroring exactly
-- how 0024 attached home_team_id/away_team_id to the same table.
-- ---------------------------------------------------------------------
alter table competition.fixture_schedules
  add column if not exists league_id uuid
    references football_data.leagues (id) on delete set null;

comment on column competition.fixture_schedules.league_id is
  'Optional league this fixture was played in, into football_data.leagues '
  '(migration 0027). Null for every schedule row registered before this '
  'migration and for any client not yet sending it — the matches card '
  'falls back to showing no league name at all rather than guessing one.';

create index if not exists fixture_schedules_league_id_idx
  on competition.fixture_schedules (league_id);
'''

with open(TARGET, "w", encoding="utf-8") as f:
    f.write(SQL)
print("created supabase/migrations/0027_fixture_league.sql")

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 35_leagues_migration (1/4): بطاقة المباراة تعرض «شهر 9» "
    "لا اسم الدوري لأن اسم الدوري غير موجود في البيانات أصلًا: "
    "SeasonFixtureCardDto يحمل الموسم والمباراة واسمي الفريقين والانطلاق "
    "فقط، وfootball_data.teams بلا رابط دوري. أُضيفت هجرة 0027: جدول "
    "football_data.leagues (اسم + شعار، بنفس شكل teams وسياسة RLS نفسها) "
    "وعمود league_id اختياري على competition.fixture_schedules على نمط "
    "0024 حرفيًا. قراران مسجَّلان: (1) هذا يُنهي تأجيل tournament في "
    "ADR-003 §2.2 — 0013 أجّله لأن «لا شيء في واجهة v1 يستهلك بيانات "
    "البطولة» وطلب مراجعته عند الحاجة، وقد حانت، فأُضيف في أنحف صورة: "
    "هوية عرض فقط بلا شكل موسم ولا مرجع مزوّد. (2) لم يُربط بـ"
    "competition.competitions رغم وجود ثمانية صفوف بأسماء دوريات فيه، لأن "
    "ذلك الجدول صار يعني «مسابقة ينضم إليها المستخدمون ويجمعون فيها "
    "نقاطًا» ويضمّ «شهر 9» — فكان league_id سيقبل مسابقة شهرية كدوري. "
    "الدوري واقع كروي لا بنية مسابقة، فمكانه football_data بجوار teams. "
    "Axiom 3 سليم: football_data.fixtures ما زال بلا مرجع مسابقة. الهجرة "
    "توسيعية بحتة ولا تغيّر سلوكًا وحدها؛ الملء الخلفي للمباريات الـ21 "
    "وقائمة الاختيار في لوحة المشرف والعرض في البطاقة دفعات 2 و3 و4 — "
    "supabase/migrations/0027_fixture_league.sql\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = ["supabase/migrations/0027_fixture_league.sql", "docs/checkpoints/session-log.md"]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "feat(db): add football_data.leagues and fixture_schedules.league_id"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
