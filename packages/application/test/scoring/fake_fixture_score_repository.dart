import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A complete in-memory [FixtureScoreRepository] for use-case tests.
///
/// Reproduces the observable contract: idempotent upsert per
/// `(fixture, participant)` (re-scoring replaces in place, never
/// duplicates), and a stable by-fixture read ordered by participant id. It
/// never throws.
final class FakeFixtureScoreRepository implements FixtureScoreRepository {
  /// keyed by `${fixtureId}|${participantId}`.
  final Map<String, ParticipantFixtureScore> _byKey = {};

  AppError? _scriptedFailure;

  /// Scripts the *next* call to fail with [error], then clears the script.
  void failNextWith(AppError error) => _scriptedFailure = error;

  AppError? _takeFailure() {
    final f = _scriptedFailure;
    _scriptedFailure = null;
    return f;
  }

  static String _key(FixtureRef fixture, ParticipantId participantId) =>
      '${fixture.value}|${participantId.value}';

  /// How many fixture-score rows are stored (proves idempotent re-scoring
  /// keeps one row per participant).
  int get count => _byKey.length;

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final staged = <String, ParticipantFixtureScore>{};
    for (final s in scores) {
      staged[_key(s.fixture, s.participantId)] = s;
    }
    _byKey.addAll(staged);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final out = <ParticipantFixtureScore>[
      for (final s in _byKey.values)
        if (s.fixture == fixture) s,
    ]..sort((a, b) => a.participantId.value.compareTo(b.participantId.value));
    return Result.ok(out);
  }
}
