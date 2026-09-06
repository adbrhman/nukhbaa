#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""36_league_on_fixture_card — دفعة 3/4: اسم الدوري وشعاره عبر الطبقات."""
import os, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
assert os.path.isdir(os.path.join(ROOT, "packages/domain")), "not the monorepo root"


def patch(rel, old, new, count=1):
    p = os.path.join(ROOT, rel)
    with open(p, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == count, "anchor x%d != %d in %s" % (s.count(old), count, rel)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new, count))
    print("patched", rel)


# ============================================================ 1. domain
FS = "packages/domain/lib/src/competition/fixture_schedule.dart"

patch(
    FS,
    """  const FixtureSchedule.fromStored({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.homeTeamId,
    this.awayTeamId,
  });""",
    """  /// Rebuilds a stored schedule.
  ///
  /// [leagueName]/[leagueLogoUrl] are **read-only** enrichment resolved by
  /// the repository's join onto `football_data.leagues` (migration 0027).
  /// They are deliberately absent from [create] and never written back: the
  /// schedule row stores a `league_id`, not a name — denormalising the two
  /// display fields onto the read is the same shape
  /// `CurrentMonthFixtureEntry` already uses for `competitionName`, and it
  /// spares the client a second catalog round-trip for one label.
  const FixtureSchedule.fromStored({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.homeTeamId,
    this.awayTeamId,
    this.leagueName,
    this.leagueLogoUrl,
  });""",
)

patch(
    FS,
    """  final TeamRef? homeTeamId;
  final TeamRef? awayTeamId;

  @override
  bool operator ==(Object other) =>
      other is FixtureSchedule &&""",
    """  final TeamRef? homeTeamId;
  final TeamRef? awayTeamId;

  /// The league this fixture was played in, or `null` when the schedule
  /// carries no `league_id` yet. Read-only (see [FixtureSchedule.fromStored]).
  final String? leagueName;

  /// The league's logo URL, same nullability and provenance as [leagueName].
  final String? leagueLogoUrl;

  @override
  bool operator ==(Object other) =>
      other is FixtureSchedule &&""",
)

patch(
    FS,
    """      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId;

  @override
  int get hashCode => Object.hash(
    fixture,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
  );""",
    """      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId &&
      other.leagueName == leagueName &&
      other.leagueLogoUrl == leagueLogoUrl;

  @override
  int get hashCode => Object.hash(
    fixture,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
    leagueName,
    leagueLogoUrl,
  );""",
)

SFC = "packages/domain/lib/src/competition/season_fixture_card.dart"

patch(
    SFC,
    """    this.homeTeamId,
    this.awayTeamId,
  });""",
    """    this.homeTeamId,
    this.awayTeamId,
    this.leagueName,
    this.leagueLogoUrl,
  });""",
)

patch(
    SFC,
    """  /// The away side's resolved team id, same nullability as [homeTeamId].
  final TeamRef? awayTeamId;""",
    """  /// The away side's resolved team id, same nullability as [homeTeamId].
  final TeamRef? awayTeamId;

  /// The league this fixture was played in ("الدوري الإنجليزي الممتاز"), or
  /// `null` when the schedule carries no league yet. This is the football
  /// competition, NOT the contest the fixture scores into — the contest is
  /// the calendar month and travels separately as
  /// `CurrentMonthFixtureEntry.competitionName`.
  final String? leagueName;

  /// The league's logo URL, same nullability as [leagueName].
  final String? leagueLogoUrl;""",
)

patch(
    SFC,
    """      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId;

  @override
  int get hashCode => Object.hash(
    seasonId,
    fixtureId,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
  );""",
    """      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId &&
      other.leagueName == leagueName &&
      other.leagueLogoUrl == leagueLogoUrl;

  @override
  int get hashCode => Object.hash(
    seasonId,
    fixtureId,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
    leagueName,
    leagueLogoUrl,
  );""",
)

# ==================================================== 2. infrastructure
REPO = "packages/infrastructure/lib/src/competition/postgres_fixture_schedule_repository.dart"

# LEFT JOIN, never INNER: a fixture with no league must still come back.
patch(
    REPO,
    """  static const String _selectByFixtureSql = '''
SELECT fixture_id, home_team, away_team, kickoff_at, home_team_id,
       away_team_id
FROM competition.fixture_schedules
WHERE fixture_id = @fixture_id
''';""",
    """  // LEFT JOIN, never INNER: a fixture whose league_id is null (every row
  // registered before migration 0027) must still come back, with null league
  // columns — an inner join here would silently hide fixtures from the feed.
  static const String _selectByFixtureSql = '''
SELECT fs.fixture_id, fs.home_team, fs.away_team, fs.kickoff_at,
       fs.home_team_id, fs.away_team_id,
       l.name AS league_name, l.logo_url AS league_logo_url
FROM competition.fixture_schedules fs
LEFT JOIN football_data.leagues l ON l.id = fs.league_id
WHERE fs.fixture_id = @fixture_id
''';""",
)

patch(
    REPO,
    """  static const String _selectByFixturesSql = '''
SELECT fixture_id, home_team, away_team, kickoff_at, home_team_id,
       away_team_id
FROM competition.fixture_schedules
WHERE fixture_id = ANY(@fixture_ids::uuid[])
''';""",
    """  static const String _selectByFixturesSql = '''
SELECT fs.fixture_id, fs.home_team, fs.away_team, fs.kickoff_at,
       fs.home_team_id, fs.away_team_id,
       l.name AS league_name, l.logo_url AS league_logo_url
FROM competition.fixture_schedules fs
LEFT JOIN football_data.leagues l ON l.id = fs.league_id
WHERE fs.fixture_id = ANY(@fixture_ids::uuid[])
''';""",
)

patch(
    REPO,
    """    return Result.ok(
      FixtureSchedule.fromStored(
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoffAt: kickoffAt,
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
      ),
    );""",
    """    // The two league columns are display strings off a LEFT JOIN: absent
    // (null) is the normal state, and a non-string would mean the join
    // itself is wrong, so they are read defensively rather than validated
    // into a typed failure the way the identity columns above are.
    final leagueName = row['league_name'];
    final leagueLogoUrl = row['league_logo_url'];

    return Result.ok(
      FixtureSchedule.fromStored(
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoffAt: kickoffAt,
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
        leagueName: leagueName is String ? leagueName : null,
        leagueLogoUrl: leagueLogoUrl is String ? leagueLogoUrl : null,
      ),
    );""",
)

# ======================================================= 3. application
patch(
    "packages/application/lib/src/competition/list_current_month_fixtures.dart",
    """              homeTeamId: byFixture[fixture.value]?.homeTeamId,
              awayTeamId: byFixture[fixture.value]?.awayTeamId,
            ),""",
    """              homeTeamId: byFixture[fixture.value]?.homeTeamId,
              awayTeamId: byFixture[fixture.value]?.awayTeamId,
              leagueName: byFixture[fixture.value]?.leagueName,
              leagueLogoUrl: byFixture[fixture.value]?.leagueLogoUrl,
            ),""",
)

patch(
    "packages/application/lib/src/competition/browse_season_fixtures.dart",
    """          homeTeamId: byFixture[fixture.value]?.homeTeamId,
          awayTeamId: byFixture[fixture.value]?.awayTeamId,
        ),""",
    """          homeTeamId: byFixture[fixture.value]?.homeTeamId,
          awayTeamId: byFixture[fixture.value]?.awayTeamId,
          leagueName: byFixture[fixture.value]?.leagueName,
          leagueLogoUrl: byFixture[fixture.value]?.leagueLogoUrl,
        ),""",
)

# ========================================================= 4. contracts
DTO = "packages/contracts/lib/src/competition_dto.dart"

patch(
    DTO,
    """    this.homeTeamId,
    this.awayTeamId,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory SeasonFixtureCardDto.fromJson(Map<String, Object?> json) {""",
    """    this.homeTeamId,
    this.awayTeamId,
    this.leagueName,
    this.leagueLogoUrl,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory SeasonFixtureCardDto.fromJson(Map<String, Object?> json) {""",
)

patch(
    DTO,
    """      homeTeamId: json['home_team_id'] as String?,
      awayTeamId: json['away_team_id'] as String?,
    );
  }""",
    """      homeTeamId: json['home_team_id'] as String?,
      awayTeamId: json['away_team_id'] as String?,
      leagueName: json['league_name'] as String?,
      leagueLogoUrl: json['league_logo_url'] as String?,
    );
  }""",
)

patch(
    DTO,
    """  /// The away side's resolved Football Data team id, or `null` when unknown.
  final String? awayTeamId;

  /// The schema version of this payload.
  final int schemaVersion;""",
    """  /// The away side's resolved Football Data team id, or `null` when unknown.
  final String? awayTeamId;

  /// The league this fixture was played in, or `null` when unknown. Not the
  /// contest it scores into — that is the month, carried separately.
  final String? leagueName;

  /// The league's logo URL, or `null` when unknown.
  final String? leagueLogoUrl;

  /// The schema version of this payload.
  final int schemaVersion;""",
)

patch(
    DTO,
    """    'home_team_id': homeTeamId,
    'away_team_id': awayTeamId,
  };""",
    """    'home_team_id': homeTeamId,
    'away_team_id': awayTeamId,
    'league_name': leagueName,
    'league_logo_url': leagueLogoUrl,
  };""",
)

patch(
    DTO,
    """      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    seasonId,
    fixtureId,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
    schemaVersion,
  );""",
    """      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId &&
      other.leagueName == leagueName &&
      other.leagueLogoUrl == leagueLogoUrl &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    seasonId,
    fixtureId,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
    leagueName,
    leagueLogoUrl,
    schemaVersion,
  );""",
)

# ============================================================ 5. server
patch(
    "apps/server/lib/http/competition_dto_mapper.dart",
    """    homeTeamId: card.homeTeamId?.value,
    awayTeamId: card.awayTeamId?.value,
  );
}""",
    """    homeTeamId: card.homeTeamId?.value,
    awayTeamId: card.awayTeamId?.value,
    leagueName: card.leagueName,
    leagueLogoUrl: card.leagueLogoUrl,
  );
}""",
)

# ============================================================ 6. mobile
CARD = "apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart"

patch(
    CARD,
    """                _CardHeader(
                  competitionId: widget.item.competitionId,
                  competitionName: widget.item.competitionName,""",
    """                _CardHeader(
                  // The league the match was played in when known, falling
                  // back to the contest's own name ("شهر 9") only while a
                  // fixture still carries no league. The reference design
                  // shows the league here, never the contest.
                  competitionId: widget.item.competitionId,
                  competitionName:
                      _fixture.leagueName ?? widget.item.competitionName,
                  leagueLogoUrl: _fixture.leagueLogoUrl,""",
)

patch(
    CARD,
    """  const _CardHeader({
    required this.competitionId,
    required this.competitionName,
    required this.kickoffAt,
    required this.onOpenLeaderboard,
  });

  final String competitionId;
  final String competitionName;""",
    """  const _CardHeader({
    required this.competitionId,
    required this.competitionName,
    required this.leagueLogoUrl,
    required this.kickoffAt,
    required this.onOpenLeaderboard,
  });

  final String competitionId;
  final String competitionName;

  /// The league's own logo when the fixture carries one — preferred over the
  /// bundled per-competition asset, which ships empty.
  final String? leagueLogoUrl;""",
)

patch(
    CARD,
    """              _CompetitionLogo(assetPath: assetPath),""",
    """              _CompetitionLogo(assetPath: assetPath, logoUrl: leagueLogoUrl),""",
)

patch(
    CARD,
    """class _CompetitionLogo extends StatelessWidget {
  const _CompetitionLogo({required this.assetPath});

  final String? assetPath;

  static const double _size = 16;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (assetPath != null) {""",
    """class _CompetitionLogo extends StatelessWidget {
  const _CompetitionLogo({required this.assetPath, this.logoUrl});

  final String? assetPath;

  /// A remote league logo (`football_data.leagues.logo_url`, migration
  /// 0027). Preferred over [assetPath] because the bundled asset map ships
  /// empty; falls through to the trophy glyph on a network/decode failure,
  /// exactly as the asset path does.
  final String? logoUrl;

  static const double _size = 16;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final String? url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: _size,
          height: _size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _fallback(tokens),
        ),
      );
    }
    if (assetPath != null) {""",
)

for rel in (
    FS, SFC, REPO,
    "packages/application/lib/src/competition/list_current_month_fixtures.dart",
    "packages/application/lib/src/competition/browse_season_fixtures.dart",
    DTO,
    "apps/server/lib/http/competition_dto_mapper.dart",
    CARD,
):
    subprocess.run(["dart", "format", os.path.join(ROOT, rel)], check=True)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 36_league_on_fixture_card (3/4): اسم الدوري وشعاره صارا "
    "يسافران مع بطاقة المباراة عبر ستّ طبقات، فترويسة البطاقة تعرض «الدوري "
    "الإنجليزي الممتاز» بدل «شهر 9». قرار التصميم: تسطيح الاسم والشعار على "
    "القراءة بدل إضافة كيان League ومنفذ ومستودع ومسار /leagues وDTO ومزوّد "
    "في الموبايل على نمط الفرق — ثمانية مصنوعات مقابل عمودين، ولها سابقة في "
    "المشروع نفسه: CurrentMonthFixtureEntry يحمل competitionName مسطَّحًا لا "
    "معرّفًا فقط. الضمّ LEFT لا INNER عمدًا: مباراة بلا league_id (كل صفّ "
    "سابق للهجرة 0027) يجب أن تعود بأعمدة دوري فارغة لا أن تختفي من "
    "التغذية صامتةً. عمودا الدوري يُقرآن دفاعيًا (is String) لا يُتحقَّق "
    "منهما كأعمدة الهوية، لأن غيابهما حالة طبيعية لا فساد بيانات. "
    "leagueName/leagueLogoUrl غائبان عن FixtureSchedule.create ولا يُكتبان "
    "أبدًا — الصفّ يخزّن league_id لا اسمًا. والبطاقة تفضّل شعار الدوري "
    "البعيد على أصل competition_logo_assets.dart لأنه يُشحن فارغًا، وترتدّ "
    "إلى رمز الكأس عند فشل الشبكة. مؤجَّل للدفعة 4/4: قائمة اختيار الدوري "
    "في لوحة المشرف وكتابة league_id عند upsert — المباريات الـ21 القائمة "
    "مُلئت بـSQL مباشرة، فالمطلوب للمباريات الجديدة وحدها. وlogo_url ما "
    "زال فارغًا للدوريات الستة، فيظهر الاسم بلا شعار حتى يُملأ — "
    "packages/domain/lib/src/competition/fixture_schedule.dart, "
    "packages/domain/lib/src/competition/season_fixture_card.dart, "
    "packages/infrastructure/lib/src/competition/postgres_fixture_schedule_repository.dart, "
    "packages/application/lib/src/competition/list_current_month_fixtures.dart, "
    "packages/application/lib/src/competition/browse_season_fixtures.dart, "
    "packages/contracts/lib/src/competition_dto.dart, "
    "apps/server/lib/http/competition_dto_mapper.dart, "
    "apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    FS, SFC, REPO,
    "packages/application/lib/src/competition/list_current_month_fixtures.dart",
    "packages/application/lib/src/competition/browse_season_fixtures.dart",
    DTO,
    "apps/server/lib/http/competition_dto_mapper.dart",
    CARD,
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "feat: carry the league name and logo on the fixture card"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
