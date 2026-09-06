#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""39_fix_unlink_fakes — استيراد ناقص + ثمانية مزيّفات + اختبارات الحارسين."""
import os, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
assert os.path.isdir(os.path.join(ROOT, "packages/domain")), "not the monorepo root"


def write(rel, content):
    p = os.path.join(ROOT, rel)
    assert not os.path.exists(p), "%s already exists" % rel
    with open(p, "w", encoding="utf-8") as f:
        f.write(content)
    print("created", rel)


def patch(rel, old, new, count=1):
    p = os.path.join(ROOT, rel)
    with open(p, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == count, "anchor x%d != %d in %s" % (s.count(old), count, rel)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new, count))
    print("patched", rel)


# --------------------------------------------------- 1. the missing import
# FixturePredictionView lives in `application`, not `domain` — the use-case
# imported neither, so `List<FixturePredictionView>` was an unknown type.
patch(
    "packages/application/lib/src/competition/remove_fixture_from_season.dart",
    "import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';",
    "import 'package:application/src/prediction/fixture_prediction_view.dart';\n"
    "import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';",
)

# ------------------------------------------- 2. the application-test fake
# This one gets a REAL implementation: the use-case tests below assert the
# link is actually gone, and that a second removal reports false.
patch(
    "packages/application/test/prediction/fake_fixture_prediction_repository.dart",
    """    _seasonFixtures[key] = link;
    return const Result.ok(null);
  }
""",
    """    _seasonFixtures[key] = link;
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final removed = _seasonFixtures.remove(
      '${seasonId.value}|${fixture.value}',
    );
    return Result.ok(removed != null);
  }
""",
)

# ------------------------------------------------ 3. the six server fakes
# These never exercise the method — their route tests cover other paths — so
# each gets the honest minimum: the not-linked answer, no hidden state.
STUB = """
  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async => const Result.ok(false);
"""

SERVER_FAKES = [
    "apps/server/test/routes/admin/fixtures/admin_fixtures_predictions_route_test.dart",
    "apps/server/test/routes/feed/current_month_fixtures_test.dart",
    "apps/server/test/routes/fixture_prediction_scoring_test.dart",
    "apps/server/test/routes/fixture_scores_route_test.dart",
    "apps/server/test/routes/scoring_routes_test.dart",
    "apps/server/test/routes/season_fixtures_link_test.dart",
]
for rel in SERVER_FAKES:
    p = os.path.join(ROOT, rel)
    with open(p, encoding="utf-8") as f:
        s = f.read()
    marker = "Future<Result<void>> linkFixtureToSeason("
    assert s.count(marker) == 1, "linkFixtureToSeason x%d in %s" % (s.count(marker), rel)
    # Insert after that method ends. Bodies differ across these fakes — some
    # are arrow-bodied, some braced — so anchor on the blank line before the
    # next @override rather than guessing a closing-brace shape.
    start = s.index(marker)
    end = s.index("\n\n  @override", start) + 1
    s = s[:end] + STUB + s[end:]
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("patched", rel)

# ------------------------------------------------------ 4. use-case tests
TEST = r'''import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../scoring/fakes.dart';
import 'fake_competition_repository.dart';
import 'fakes.dart';

const _adminId = '11111111-1111-1111-1111-111111111111';
const _competitionId = '22222222-2222-2222-2222-222222222222';
const _seasonId = '33333333-3333-3333-3333-333333333333';
const _fixtureId = '44444444-4444-4444-4444-444444444444';
const _predictionId = '55555555-5555-5555-5555-555555555555';
const _participantId = '66666666-6666-6666-6666-666666666666';

CompetitionSeason _season() =>
    (CompetitionSeason.create(
              id: const SeasonId(_seasonId),
              competitionId: const CompetitionId(_competitionId),
              label: '09/2026',
              startAt: DateTime.utc(2026, 9),
              endAt: DateTime.utc(2026, 10),
            )
            as Ok<CompetitionSeason>)
        .value;

SeasonFixture _link() =>
    (SeasonFixture.create(
              seasonId: const SeasonId(_seasonId),
              fixture: const FixtureRef(_fixtureId),
              displayOrder: 0,
            )
            as Ok<SeasonFixture>)
        .value;

void main() {
  late FakeCompetitionRepository competitionRepo;
  late FakeFixturePredictionRepository predictions;
  late FakeFixtureResultRepository results;
  late RemoveFixtureFromSeason useCase;

  setUp(() {
    competitionRepo = FakeCompetitionRepository();
    predictions = FakeFixturePredictionRepository();
    results = FakeFixtureResultRepository();
    useCase = RemoveFixtureFromSeason(
      competitionRepository: competitionRepo,
      fixturePredictionRepository: predictions,
      fixtureResultRepository: results,
    );
    competitionRepo.seedSeason(_season());
  });

  Future<Result<bool>> remove({String? principalId}) => useCase(
    principal: adminPrincipal(principalId ?? _adminId),
    seasonId: _seasonId,
    fixtureId: _fixtureId,
  );

  test('admin removes an untouched fixture from the season', () async {
    predictions.seedSeasonFixture(_link());

    expect((await remove() as Ok<bool>).value, isTrue);

    final gone = await predictions.findSeasonFixture(
      const SeasonId(_seasonId),
      const FixtureRef(_fixtureId),
    );
    expect((gone as Ok<SeasonFixture?>).value, isNull);
  });

  test('removing an already-removed link converges on false', () async {
    predictions.seedSeasonFixture(_link());
    await remove();

    // Idempotent, not an error: a retried removal must not fail.
    expect((await remove() as Ok<bool>).value, isFalse);
  });

  test('refuses once anyone has predicted the fixture', () async {
    predictions
      ..seedSeasonFixture(_link())
      ..seedPrediction(
        FixturePrediction.fromStored(
          id: const PredictionId(_predictionId),
          fixture: const FixtureRef(_fixtureId),
          participantId: const ParticipantId(_participantId),
          homeGoals: 2,
          awayGoals: 1,
        ),
        DateTime.utc(2026, 9, 5),
      );

    final error = (await remove() as Err<bool>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'competition.fixture_has_predictions');

    // The guard must REFUSE, never cascade: the link is still there, so the
    // ledger can never end up holding points for a fixture no screen shows.
    final still = await predictions.findSeasonFixture(
      const SeasonId(_seasonId),
      const FixtureRef(_fixtureId),
    );
    expect((still as Ok<SeasonFixture?>).value, isNotNull);
  });

  test('refuses once a result is recorded, even with no predictions', () async {
    predictions.seedSeasonFixture(_link());
    results.seed(
      (FixtureResult.create(
                fixture: const FixtureRef(_fixtureId),
                homeGoals: 1,
                awayGoals: 0,
              )
              as Ok<FixtureResult>)
          .value,
    );

    final error = (await remove() as Err<bool>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'competition.fixture_result_already_recorded');
  });

  test('non-admin is rejected before any read', () async {
    predictions.seedSeasonFixture(_link());

    final result = await useCase(
      principal: userPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: _fixtureId,
    );

    expect((result as Err<bool>).error.kind, ErrorKind.authorization);
    final still = await predictions.findSeasonFixture(
      const SeasonId(_seasonId),
      const FixtureRef(_fixtureId),
    );
    expect((still as Ok<SeasonFixture?>).value, isNotNull);
  });

  test('rejects a malformed fixture id', () async {
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      seasonId: _seasonId,
      fixtureId: 'not-a-uuid',
    );
    expect((result as Err<bool>).error.kind, ErrorKind.validation);
  });
}
'''
write("packages/application/test/competition/remove_fixture_from_season_test.dart", TEST)

TOUCHED = [
    "packages/application/lib/src/competition/remove_fixture_from_season.dart",
    "packages/application/test/prediction/fake_fixture_prediction_repository.dart",
    "packages/application/test/competition/remove_fixture_from_season_test.dart",
] + SERVER_FAKES
for rel in TOUCHED:
    subprocess.run(["dart", "format", os.path.join(ROOT, rel)], check=True)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 39_fix_unlink_fakes: تسعة أخطاء من دفعة 38، صنفان. "
    "الأول خطأ صريح: RemoveFixtureFromSeason استعمل FixturePredictionView "
    "بلا استيراد — النوع في application لا في domain، ولم يكشفه إلا التحليل "
    "على الجذر لأن flutter test في apps/mobile لا يمسّ الحزم. الثاني أثر "
    "متوقّع لتوسيع منفذ: ثمانية مزيّفات تنفّذ FixturePredictionRepository "
    "صارت ناقصة. الستة في apps/server/test أخذت أبسط تنفيذ صادق "
    "(Ok(false) = لا رابط) لأن اختباراتها لا تمسّ الطريقة، أما مزيّف "
    "application فأخذ تنفيذًا حقيقيًا يحذف من متجره لأن اختبارات حالة "
    "الاستخدام تعتمد عليه. وأُضيفت ستة اختبارات للحارسين: الحذف السعيد، "
    "والتكرار يعود Ok(false) لا خطأ، ورفض التوقّع القائم مع التوكيد أن "
    "الرابط ما زال موجودًا بعد الرفض (الحارس يرفض ولا يتتالى — وهذا هو "
    "التوكيد الذي يحمي الدفتر من نقاط لمباراة لا تعرضها شاشة)، ورفض النتيجة "
    "المسجَّلة بلا أي توقّع (لذلك يُفحص الحارسان كلاهما لا أحدهما)، ورفض "
    "غير المشرف، ومعرّف مباراة مشوّه — "
    + ", ".join(TOUCHED) + "\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = TOUCHED + ["docs/checkpoints/session-log.md"]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "fix: wire the new unlink port through every fake, and cover both guards"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
