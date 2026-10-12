import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// Short-lived, in-process caches in front of the two prediction reads every
/// player's screen repeats for the same fixture: whether the fixture belongs
/// to the season (the gate of the scores, predictions and board routes) and,
/// once it has kicked off, everyone's predictions for it.
///
/// Both answers are the same for every player: a season's fixture list
/// changes only when an admin links or unlinks a match, and the predictions
/// of a fixture are frozen at its kickoff -- `ListFixturePredictions` reads
/// them only after that. Concurrent reads of the same answer share one query
/// ([ReadCoalescer]); a successful answer serves every request for its ttl.
/// Failures are never cached.
///
/// Wired into the read use-cases only (the scores, predictions and board
/// routes); submitting a prediction and the admin's season links keep the
/// plain repository. A link changed elsewhere therefore takes up to
/// [linkTtl] to show here. The writes are still passed through, and drop
/// what they touch, should a writer ever be handed this decorator.
final class CachedFixturePredictionReads
    implements FixturePredictionRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixturePredictionReads(
    this._inner, {
    Duration linkTtl = const Duration(seconds: 60),
    Duration predictionsTtl = const Duration(seconds: 20),
    int maxEntries = 512,
    DateTime Function() now = DateTime.now,
  }) : _links = TtlCache<String, _Link>(
         ttl: linkTtl,
         maxEntries: maxEntries,
         now: now,
       ),
       _predictions = TtlCache<String, List<FixturePredictionView>>(
         ttl: predictionsTtl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixturePredictionRepository _inner;
  final TtlCache<String, _Link> _links;
  final TtlCache<String, List<FixturePredictionView>> _predictions;
  final ReadCoalescer<String, Result<SeasonFixture?>> _linkLoads =
      ReadCoalescer<String, Result<SeasonFixture?>>();
  final ReadCoalescer<String, Result<List<FixturePredictionView>>>
  _predictionLoads =
      ReadCoalescer<String, Result<List<FixturePredictionView>>>();

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) {
    final String key = '${seasonId.value}|${fixture.value}';
    final _Link? cached = _links.read(key);
    if (cached != null) {
      return Future<Result<SeasonFixture?>>.value(
        Result<SeasonFixture?>.ok(cached.link),
      );
    }
    final int startedAt = _links.generation;
    return _linkLoads.run('$startedAt|$key', () async {
      final Result<SeasonFixture?> found = await _inner.findSeasonFixture(
        seasonId,
        fixture,
      );
      if (found case Ok<SeasonFixture?>(:final value)) {
        _links.write(key, _Link(value), startedAt: startedAt);
      }
      return found;
    });
  }

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) {
    final List<FixturePredictionView>? cached = _predictions.read(
      fixture.value,
    );
    if (cached != null) {
      return Future<Result<List<FixturePredictionView>>>.value(
        Result<List<FixturePredictionView>>.ok(cached),
      );
    }
    final int startedAt = _predictions.generation;
    return _predictionLoads.run('$startedAt|${fixture.value}', () async {
      final Result<List<FixturePredictionView>> found = await _inner
          .listByFixture(fixture);
      if (found case Ok<List<FixturePredictionView>>(:final value)) {
        _predictions.write(fixture.value, value, startedAt: startedAt);
      }
      return found;
    });
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async {
    final Result<void> result = await _inner.linkFixtureToSeason(link);
    // Cleared on failure too: a write that errored may still have landed.
    _links.clear();
    return result;
  }

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async {
    final Result<bool> result = await _inner.unlinkFixtureFromSeason(
      seasonId: seasonId,
      fixture: fixture,
    );
    _links.clear();
    return result;
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final Result<void> result = await _inner.save(prediction, submittedAt);
    _predictions.clear();
    return result;
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final Result<void> result = await _inner.update(prediction, submittedAt);
    _predictions.clear();
    return result;
  }

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) => _inner.findByFixtureAndParticipant(fixture, participantId);

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) => _inner.countDoublesOnDay(
    participantId,
    dayUtc,
    excludingFixture: excludingFixture,
  );

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) =>
      _inner.listSeasonFixtures(seasonId);

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) =>
      _inner.listByUser(userId);
}

/// A stored answer of [CachedFixturePredictionReads.findSeasonFixture], so
/// "not in this season" (`null`) can be cached as well.
final class _Link {
  const _Link(this.link);

  final SeasonFixture? link;
}
