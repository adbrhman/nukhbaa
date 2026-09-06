#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""38_remove_fixture_from_season — حذف مباراة من الموسم: الخادم (1/2)."""
import os, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
assert os.path.isdir(os.path.join(ROOT, "packages/domain")), "not the monorepo root"


def write(rel, content):
    p = os.path.join(ROOT, rel)
    assert not os.path.exists(p), "%s already exists" % rel
    os.makedirs(os.path.dirname(p), exist_ok=True)
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


# ---------------------------------------------------------------- 1. port
patch(
    "packages/application/lib/src/prediction/ports/fixture_prediction_repository.dart",
    "  Future<Result<void>> linkFixtureToSeason(SeasonFixture link);",
    """  Future<Result<void>> linkFixtureToSeason(SeasonFixture link);

  /// Removes the `(seasonId, fixture)` link — the inverse of
  /// [linkFixtureToSeason], for correcting a mistaken or duplicate link.
  ///
  /// Returns `Ok(true)` when a link was actually deleted and `Ok(false)`
  /// when there was none, so a retried removal converges instead of failing
  /// — the same idempotent contract
  /// `CompetitionRepository.deleteRoundFixture` already has.
  ///
  /// Deletes ONLY the link. The fixture's schedule row, and anything ever
  /// predicted or scored against it, are untouched; the use-case above is
  /// what refuses to unlink a fixture that has either.
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  });""",
)

# ------------------------------------------------------ 2. infrastructure
patch(
    "packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart",
    """  // --------------------------------------------------------------------------
  // countDoublesOnDay
  //""",
    """  // --------------------------------------------------------------------------
  // unlinkFixtureFromSeason — inverse of the insert above, idempotent
  //
  // RETURNING is what makes "was anything actually removed?" answerable: a
  // plain DELETE reports no rows either way through this connection wrapper,
  // so a second call could not be distinguished from a first.
  // --------------------------------------------------------------------------

  static const String _deleteSeasonFixtureSql = '''
DELETE FROM competition.season_fixtures
WHERE season_id = @season_id AND fixture_id = @fixture_id
RETURNING fixture_id
''';

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async {
    final result = await _connection.query(
      _deleteSeasonFixtureSql,
      parameters: {
        'season_id': seasonId.value,
        'fixture_id': fixture.value,
      },
    );
    return switch (result) {
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
    };
  }

  // --------------------------------------------------------------------------
  // countDoublesOnDay
  //""",
)

# --------------------------------------------------------- 3. use-case
USECASE = r'''import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: remove a fixture from a season — the inverse of
/// [LinkFixtureToSeason], and the season-scoped sibling of
/// [RemoveFixtureFromRound]. Admin-only.
///
/// ## What this is for
/// Correcting an admin's own entry mistake — a wrong team, a wrong kickoff,
/// a duplicate — in the window before anyone has acted on the fixture. It is
/// deliberately NOT a cancellation feature.
///
/// ## Why the guards are absolute
/// A season's fixtures are what the monthly leaderboard aggregates over, and
/// the ledger is append-only by construction (`ledger.reject_entry_mutation`
/// refuses every DELETE and UPDATE). So a fixture that has been predicted or
/// scored cannot be truly removed at all: unlinking it would leave points
/// standing in the ledger for a fixture no screen can show — a leaderboard
/// total nobody can account for, which is worse than the mistake being
/// corrected. Both guards therefore reject rather than cascade:
///   * any prediction exists ([FixturePredictionRepository.listByFixture])
///     -> [ErrorKind.invariant] `competition.fixture_has_predictions`
///   * a result is recorded ([FixtureResultRepository.findByFixture])
///     -> [ErrorKind.invariant] `competition.fixture_result_already_recorded`
///       (the same code [RemoveFixtureFromRound] raises, deliberately)
///
/// Both are checked even though either alone would usually be enough: a
/// result can be recorded before anyone predicts, and a prediction can exist
/// with no result yet.
///
/// The delete itself is idempotent
/// ([FixturePredictionRepository.unlinkFixtureFromSeason]): a link that is
/// already gone is `Ok(false)`, not an error, so a retried removal converges.
///
/// Never throws; returns a typed [Result].
final class RemoveFixtureFromSeason {
  /// Creates the use-case over its collaborators.
  const RemoveFixtureFromSeason({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureResultRepository fixtureResultRepository,
  }) : _competitions = competitionRepository,
       _fixturePredictions = fixturePredictionRepository,
       _fixtureResults = fixtureResultRepository;

  final CompetitionRepository _competitions;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureResultRepository _fixtureResults;

  /// Removes [fixtureId] from [seasonId]. `Ok(true)` when a link was
  /// removed, `Ok(false)` when there was nothing to remove.
  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final seasonIdResult = SeasonId.tryParse(seasonId);
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(seasonIdResult.error);
    }
    final sId = (seasonIdResult as Ok<SeasonId>).value;

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    // The season must exist (mirrors LinkFixtureToSeason's only
    // precondition — a season carries no lifecycle status to gate on).
    final seasonResult = await _competitions.findSeason(sId);
    if (seasonResult is Err<CompetitionSeason>) {
      return Result.err(seasonResult.error);
    }

    final predictions = await _fixturePredictions.listByFixture(fixture);
    if (predictions is Err<List<FixturePredictionView>>) {
      return Result.err(predictions.error);
    }
    if ((predictions as Ok<List<FixturePredictionView>>).value.isNotEmpty) {
      return const Result.err(
        AppError.invariant(
          'competition.fixture_has_predictions',
          'Users have already predicted this fixture, so it can no longer '
              'be removed from the season',
        ),
      );
    }

    final existingResult = await _fixtureResults.findByFixture(fixture);
    if (existingResult is Err<FixtureResult?>) {
      return Result.err(existingResult.error);
    }
    if ((existingResult as Ok<FixtureResult?>).value != null) {
      return const Result.err(
        AppError.invariant(
          'competition.fixture_result_already_recorded',
          'This fixture already has a recorded result and can no longer '
              'be removed from the season',
        ),
      );
    }

    return _fixturePredictions.unlinkFixtureFromSeason(
      seasonId: sId,
      fixture: fixture,
    );
  }
}
'''
write("packages/application/lib/src/competition/remove_fixture_from_season.dart", USECASE)

patch(
    "packages/application/lib/application.dart",
    "export 'src/competition/remove_fixture_from_round.dart';",
    "export 'src/competition/remove_fixture_from_round.dart';\n"
    "export 'src/competition/remove_fixture_from_season.dart';",
)

# --------------------------------------------------- 4. composition root
CR = "apps/server/lib/composition/composition_root.dart"

patch(CR, "    required this.linkFixtureToSeason,",
       "    required this.linkFixtureToSeason,\n"
       "    required this.removeFixtureFromSeason,")

patch(CR, "    LinkFixtureToSeason? linkFixtureToSeason,",
       "    LinkFixtureToSeason? linkFixtureToSeason,\n"
       "    RemoveFixtureFromSeason? removeFixtureFromSeason,")

patch(CR, "           linkFixtureToSeason ?? _absentLinkFixtureToSeason(),",
       "           linkFixtureToSeason ?? _absentLinkFixtureToSeason(),\n"
       "       removeFixtureFromSeason =\n"
       "           removeFixtureFromSeason ?? _absentRemoveFixtureFromSeason(),")

patch(
    CR,
    """  static LinkFixtureToSeason _absentLinkFixtureToSeason() =>
      LinkFixtureToSeason(
        competitionRepository: _unwiredCompetitionRepository,
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
      );""",
    """  static LinkFixtureToSeason _absentLinkFixtureToSeason() =>
      LinkFixtureToSeason(
        competitionRepository: _unwiredCompetitionRepository,
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
      );

  static RemoveFixtureFromSeason _absentRemoveFixtureFromSeason() =>
      RemoveFixtureFromSeason(
        competitionRepository: _unwiredCompetitionRepository,
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        fixtureResultRepository: _unwiredFixtureResultRepository,
      );""",
)

patch(
    CR,
    """  /// Links a fixture to a season (admin-only command; Axiom 4 Amendment —
  /// the per-fixture sibling of [linkFixtureToRound]).
  final LinkFixtureToSeason linkFixtureToSeason;""",
    """  /// Links a fixture to a season (admin-only command; Axiom 4 Amendment —
  /// the per-fixture sibling of [linkFixtureToRound]).
  final LinkFixtureToSeason linkFixtureToSeason;

  /// Removes a fixture from a season (admin-only command), refusing once the
  /// fixture carries any prediction or a recorded result — see
  /// [RemoveFixtureFromSeason] for why those are hard refusals.
  final RemoveFixtureFromSeason removeFixtureFromSeason;""",
)

patch(
    CR,
    """      linkFixtureToSeason: LinkFixtureToSeason(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
      ),""",
    """      linkFixtureToSeason: LinkFixtureToSeason(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
      ),
      removeFixtureFromSeason: RemoveFixtureFromSeason(
        competitionRepository: competitionRepository,
        fixturePredictionRepository: fixturePredictionRepository,
        fixtureResultRepository: fixtureResultRepository,
      ),""",
)

patch(
    CR,
    "  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) => _unwired();",
    "  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) => _unwired();\n"
    "\n"
    "  @override\n"
    "  Future<Result<bool>> unlinkFixtureFromSeason({\n"
    "    required SeasonId seasonId,\n"
    "    required FixtureRef fixture,\n"
    "  }) => _unwired();",
)

# ------------------------------------------------------------- 5. route
ROUTE = r'''import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `/seasons/{id}/fixtures/{fixtureId}` — the single season-fixture link.
///
/// * `DELETE` — unlink the fixture from the season (command intent
///   `RemoveFixtureFromSeason`; the season-scoped sibling of
///   `DELETE /rounds/{id}/fixtures/{fixtureId}`). Admin-only and guarded
///   inside the use-case, which refuses once the fixture carries any
///   prediction or a recorded result. Idempotent: `{"removed": false}` when
///   there was no link, which is a success, not a `404` — the same shape the
///   reaction removal already returns.
/// * anything else → `405`.
///
/// Authenticated via the `/seasons` `bearerAuth` subtree
/// (`seasons/_middleware.dart`); this route makes no authorization decision
/// of its own.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.removeFixtureFromSeason(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<bool>(:final value) => Response.json(body: {'removed': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}
'''
write("apps/server/routes/seasons/[id]/fixtures/[fixtureId]/index.dart", ROUTE)

# -------------------------------------------------------- 6. api_client
patch(
    "packages/api_client/lib/src/competition_api.dart",
    """  /// `PUT /fixtures/{id}/result` — records (or idempotently corrects) the""",
    """  /// `DELETE /seasons/{id}/fixtures/{fixtureId}` — unlinks a fixture from
  /// the season (command intent `RemoveFixtureFromSeason`), the inverse of
  /// [linkFixtureToSeason]. Admin-only, enforced inside the server use-case,
  /// which refuses once the fixture carries any prediction or a recorded
  /// result. Returns `true` when a link was actually removed and `false`
  /// when there was none — both are a success.
  Future<Result<bool>> removeFixtureFromSeason({
    required String seasonId,
    required String fixtureId,
  }) {
    return _transport.deleteObject<bool>(
      '/seasons/$seasonId/fixtures/$fixtureId',
      parse: (json) => json['removed']! as bool,
    );
  }

  /// `PUT /fixtures/{id}/result` — records (or idempotently corrects) the""",
)

TOUCHED = [
    "packages/application/lib/src/prediction/ports/fixture_prediction_repository.dart",
    "packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart",
    "packages/application/lib/src/competition/remove_fixture_from_season.dart",
    "packages/application/lib/application.dart",
    CR,
    "apps/server/routes/seasons/[id]/fixtures/[fixtureId]/index.dart",
    "packages/api_client/lib/src/competition_api.dart",
]
for rel in TOUCHED:
    subprocess.run(["dart", "format", os.path.join(ROOT, rel)], check=True)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 38_remove_fixture_from_season (1/2): لم يكن في المنصة ما "
    "يحذف مباراة من موسم إطلاقًا — الموجود RemoveFixtureFromRound يحذف من "
    "جولة، ومسابقاتك الشهرية بلا جولات. أُضيفت الحالة عبر خمس طبقات: منفذ "
    "unlinkFixtureFromSeason، وتنفيذه بـDELETE ... RETURNING (لأن الحذف "
    "المجرّد لا يبلّغ عبر غلاف الاتصال إن حُذف صفّ فعلًا، فلا يُميَّز نداء "
    "ثانٍ عن أول)، وحالة الاستخدام، والتوصيل في CompositionRoot، ومسار "
    "DELETE /seasons/{id}/fixtures/{fixtureId}، وapi_client. حارسان يرفضان "
    "ولا يتتاليان: أي توقّع قائم (fixture_has_predictions) أو نتيجة مسجَّلة "
    "(fixture_result_already_recorded، نفس رمز الأصل عمدًا). السبب بنيوي لا "
    "احترازي: زناد ledger.reject_entry_mutation يرفض كل حذف وتعديل، فمباراة "
    "توقّع عليها أحد لا تُحذف حقًّا — فكّ ربطها يترك نقاطًا قائمة في الدفتر "
    "لمباراة لا تعرضها أي شاشة، أي مجموع في لوحة المتصدرين لا يُفسَّر، وهو "
    "أسوأ من الخطأ المراد تصحيحه. الحارسان كلاهما يُفحص لأن نتيجة قد تُسجَّل "
    "قبل أن يتوقّع أحد، وتوقّعًا قد يوجد بلا نتيجة. الحذف نفسه عديم الأثر "
    "عند التكرار: رابط مفقود = Ok(false) لا خطأ ولا 404. الغرض تصحيح خطأ "
    "إدخال المشرف في نافذة ما قبل أن يتصرّف أحد، لا إلغاء مباراة (اختيار (أ) "
    "على (ب) ترك النقاط و(ج) نظام إلغاء بحقل حالة). مؤجَّل للدفعة 2/2: زرّ "
    "الحذف في لوحة المشرف داخل نطاق «تصحيح المباراة» القائم، إعادةً "
    "لاستعمال منتقي المباراة بدل زرّ حذف تحت كل صفّ — "
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
         "feat: remove a fixture from a season, refused once predicted or scored"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
