import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of a player's own prediction history
/// (`GET /me/fixture-predictions`, [FixturePredictionRepository.listByUser]).
///
/// The history is every prediction the player ever sent, so it grows every
/// day, and the app reads it again each time a screen that shows it opens.
/// On 2026-10-23 it was the read that returned the most rows of all
/// (17.4 million since 27 July), while the Supabase egress quota was
/// exceeded (script 138). One answer now serves the player's reads for
/// [ttl].
///
/// A player's own writes reach the database through here
/// (`SubmitFixturePrediction` is handed this decorator): [save] and [update]
/// drop the history of the player the prediction belongs to, so the next
/// read carries it at once. The player is known from the participant ids of
/// the history already held; a participant not seen yet (a first prediction
/// in a new month) drops every history. A change made elsewhere (a merge by
/// an admin, [forget]) shows within [ttl] at most.
///
/// Every other read and write passes straight through. Failures are never
/// cached. The cache lives in this server process only.
final class CachedPredictionHistory implements FixturePredictionRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedPredictionHistory(
    this._inner, {
    Duration ttl = const Duration(minutes: 10),
    int maxEntries = 512,
    DateTime Function() now = DateTime.now,
  }) : _histories = TtlCache<String, List<FixturePredictionView>>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixturePredictionRepository _inner;
  final TtlCache<String, List<FixturePredictionView>> _histories;
  final ReadCoalescer<String, Result<List<FixturePredictionView>>> _loads =
      ReadCoalescer<String, Result<List<FixturePredictionView>>>();

  /// The player of each participant id seen in a cached history.
  final Map<String, String> _userOf = <String, String>{};

  /// Drops every history: predictions moved without passing through here
  /// (a merge of two copies of a match).
  void forget() {
    _histories.clear();
    _userOf.clear();
  }

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) {
    final List<FixturePredictionView>? cached = _histories.read(userId.value);
    if (cached != null) {
      return Future<Result<List<FixturePredictionView>>>.value(
        Result<List<FixturePredictionView>>.ok(cached),
      );
    }
    final int startedAt = _histories.generation;
    return _loads.run('$startedAt|${userId.value}', () async {
      final Result<List<FixturePredictionView>> found = await _inner.listByUser(
        userId,
      );
      if (found case Ok<List<FixturePredictionView>>(:final value)) {
        final List<FixturePredictionView> held =
            List<FixturePredictionView>.unmodifiable(value);
        _histories.write(userId.value, held, startedAt: startedAt);
        if (startedAt == _histories.generation) {
          for (final FixturePredictionView view in held) {
            _userOf[view.prediction.participantId.value] = userId.value;
          }
        }
        return Result<List<FixturePredictionView>>.ok(held);
      }
      return found;
    });
  }

  /// Drops the history of the player [participantId] belongs to, or every
  /// history when that player is not known yet.
  void _drop(ParticipantId participantId) {
    final String? user = _userOf[participantId.value];
    if (user == null) {
      forget();
      return;
    }
    _histories.remove(user);
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final Result<void> result = await _inner.save(prediction, submittedAt);
    // Dropped on failure too: a write that errored may still have landed.
    _drop(prediction.participantId);
    return result;
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final Result<void> result = await _inner.update(prediction, submittedAt);
    _drop(prediction.participantId);
    return result;
  }

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) => _inner.findByFixtureAndParticipant(fixture, participantId);

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) => _inner.findSeasonFixture(seasonId, fixture);

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) =>
      _inner.linkFixtureToSeason(link);

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) => _inner.unlinkFixtureFromSeason(seasonId: seasonId, fixture: fixture);

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
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) => _inner.listByFixture(fixture);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) =>
      _inner.listSeasonFixtures(seasonId);
}
