import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A complete in-memory [FixturePredictionRepository] for use-case tests.
///
/// Reproduces the observable contract the Postgres adapter must honour — the
/// `(participant_id, fixture_id)` uniqueness, find/update/list semantics, the
/// season-fixture membership read, and the daily-double count — so a
/// use-case test that passes here exercises the same invariants the real
/// adapter enforces. It never throws.
final class FakeFixturePredictionRepository
    implements FixturePredictionRepository {
  /// keyed by `${fixtureId}|${participantId}`.
  final Map<String, _Stored> _byKey = {};

  /// keyed by `${seasonId}|${fixtureId}`.
  final Map<String, SeasonFixture> _seasonFixtures = {};

  /// keyed by fixtureId -> kickoff instant, so [countDoublesOnDay] can group
  /// stored doubles by the UTC calendar day of their fixture's kickoff.
  final Map<String, DateTime> _kickoffByFixture = {};

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

  // Seeding helpers.
  void seedSeasonFixture(SeasonFixture link) =>
      _seasonFixtures['${link.seasonId.value}|${link.fixture.value}'] = link;

  void seedKickoff(FixtureRef fixture, DateTime kickoffAt) =>
      _kickoffByFixture[fixture.value] = kickoffAt;

  void seedPrediction(FixturePrediction prediction, DateTime submittedAt) =>
      _byKey[_key(prediction.fixture, prediction.participantId)] = _Stored(
        prediction,
        submittedAt,
      );

  int get count => _byKey.length;

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final stored = _byKey[_key(fixture, participantId)];
    return Result.ok(
      stored == null
          ? null
          : FixturePredictionView(
              prediction: stored.prediction,
              submittedAt: stored.submittedAt,
            ),
    );
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final key = _key(prediction.fixture, prediction.participantId);
    if (_byKey.containsKey(key)) {
      return const Result.err(
        AppError.invariant('prediction.already_submitted', 'already submitted'),
      );
    }
    _byKey[key] = _Stored(prediction, submittedAt);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final key = _key(prediction.fixture, prediction.participantId);
    if (!_byKey.containsKey(key)) {
      return const Result.err(
        AppError.invariant('prediction.not_found', 'not found'),
      );
    }
    _byKey[key] = _Stored(prediction, submittedAt);
    return const Result.ok(null);
  }

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    return Result.ok(_seasonFixtures['${seasonId.value}|${fixture.value}']);
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final key = '${link.seasonId.value}|${link.fixture.value}';
    if (_seasonFixtures.containsKey(key)) {
      return const Result.err(
        AppError.invariant(
          'competition.season_fixture_already_linked',
          'already linked',
        ),
      );
    }
    _seasonFixtures[key] = link;
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    var count = 0;
    for (final stored in _byKey.values) {
      final prediction = stored.prediction;
      if (!prediction.isDouble) continue;
      if (prediction.participantId != participantId) continue;
      if (excludingFixture != null && prediction.fixture == excludingFixture) {
        continue;
      }
      final kickoff = _kickoffByFixture[prediction.fixture.value];
      if (kickoff == null) continue;
      final sameDay =
          kickoff.year == dayUtc.year &&
          kickoff.month == dayUtc.month &&
          kickoff.day == dayUtc.day;
      if (sameDay) count++;
    }
    return Result.ok(count);
  }

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    return Result.ok([
      for (final s in _byKey.values)
        if (s.prediction.fixture == fixture)
          FixturePredictionView(
            prediction: s.prediction,
            submittedAt: s.submittedAt,
          ),
    ]);
  }

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) async {
    final f = _takeFailure();
    if (f != null) return Result.err(f);
    final links = [
      for (final link in _seasonFixtures.values)
        if (link.seasonId == seasonId) link,
    ]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return Result.ok([for (final link in links) link.fixture]);
  }
}

final class _Stored {
  const _Stored(this.prediction, this.submittedAt);
  final FixturePrediction prediction;
  final DateTime submittedAt;
}
