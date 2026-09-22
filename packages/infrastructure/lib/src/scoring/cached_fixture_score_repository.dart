import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of [FixtureScoreRepository.listByFixture].
///
/// A fixture's scores are written once when it is settled (and again only if
/// its result is corrected), yet every open of a history or prediction card
/// read them again, which made this the largest source of rows leaving the
/// database. Every score write passes through [saveFixtureScores] here, so
/// the cached list is dropped the moment it changes; [ttl] only bounds an
/// edit made outside this server.
final class CachedFixtureScoreRepository implements FixtureScoreRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixtureScoreRepository(
    this._inner, {
    Duration ttl = const Duration(minutes: 5),
    int maxEntries = 512,
    DateTime Function() now = DateTime.now,
  }) : _byFixture = TtlCache<String, List<ParticipantFixtureScore>>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixtureScoreRepository _inner;
  final TtlCache<String, List<ParticipantFixtureScore>> _byFixture;

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async {
    final Result<void> result = await _inner.saveFixtureScores(scores);
    // Evicted on failure too: a write that errored may still have landed.
    for (final String fixtureId in {
      for (final score in scores) score.fixture.value,
    }) {
      _byFixture.remove(fixtureId);
    }
    return result;
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final List<ParticipantFixtureScore>? cached = _byFixture.read(
      fixture.value,
    );
    if (cached != null) {
      return Result.ok(cached);
    }
    final int startedAt = _byFixture.generation;
    final Result<List<ParticipantFixtureScore>> result = await _inner
        .listByFixture(fixture);
    if (result case Ok<List<ParticipantFixtureScore>>(:final value)) {
      _byFixture.write(fixture.value, value, startedAt: startedAt);
    }
    return result;
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listBySeasonFixtures(
    List<FixtureRef> fixtures,
  ) => _inner.listBySeasonFixtures(fixtures);
}
