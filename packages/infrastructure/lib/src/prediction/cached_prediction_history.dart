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
/// (`SubmitFixturePrediction` is handed this decorator). A [save] or an
/// [update] that succeeded is written into the history held for that player
/// (the row the database now holds: the same goals, double and submission
/// time, the season of the player's other predictions under that
/// participant), so the read the app makes right after a save costs no
/// query (script 141: 1504 saves stood behind 3256 history reads, about 301
/// rows each, in the day and a half after script 138). The player is known
/// from the participant ids of the history already held. The history is
/// dropped instead, and read again on the next request, when the write
/// failed (it may still have landed), when no history is held for that
/// player, when the participant is not known yet (a first prediction in a
/// new month drops every history) and when an id is not in the lower-case
/// form the database returns. A merge by an admin calls [forget]; a change
/// made outside this server shows within [ttl] at most.
///
/// Every write also calls [onFixtureWritten] with its fixture, failed ones
/// too, so a cache of that fixture's predictions elsewhere (the feed's
/// win-share split) drops it (script 155).
///
/// Every other read and write passes straight through. Failures are never
/// cached. The cache lives in this server process only.
final class CachedPredictionHistory implements FixturePredictionRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedPredictionHistory(
    this._inner, {
    Duration ttl = const Duration(minutes: 30),
    int maxEntries = 512,
    DateTime Function() now = DateTime.now,
    void Function(FixtureRef fixture)? onFixtureWritten,
  }) : _onFixtureWritten = onFixtureWritten,
       _histories = TtlCache<String, List<FixturePredictionView>>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixturePredictionRepository _inner;
  final void Function(FixtureRef fixture)? _onFixtureWritten;
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

  /// Writes [prediction], just stored at [submittedAt], into the history held
  /// for its player, or drops that history when it cannot (see the class
  /// comment).
  void _afterWrite(
    FixturePrediction prediction,
    DateTime submittedAt,
    Result<void> result,
  ) {
    _onFixtureWritten?.call(prediction.fixture);
    final List<FixturePredictionView>? updated = result is Ok<void>
        ? _withWrite(prediction, submittedAt.toUtc())
        : null;
    final String? user = _userOf[prediction.participantId.value];
    if (updated == null || user == null) {
      // Dropped on failure too: a write that errored may still have landed.
      _drop(prediction.participantId);
      return;
    }
    _histories.replace(user, List<FixturePredictionView>.unmodifiable(updated));
  }

  /// The history held for the player of [prediction] with [prediction] in
  /// it, in the database's order (newest submission first, then by id); or
  /// `null` when it cannot be built from what is held.
  List<FixturePredictionView>? _withWrite(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) {
    final String participant = prediction.participantId.value;
    final String? user = _userOf[participant];
    final List<FixturePredictionView>? held = user == null
        ? null
        : _histories.read(user);
    if (held == null) {
      return null;
    }
    for (final String id in <String>[
      prediction.id.value,
      prediction.fixture.value,
      participant,
    ]) {
      if (id != id.toLowerCase()) {
        return null;
      }
    }
    FixturePredictionView? sibling;
    for (final FixturePredictionView view in held) {
      if (view.prediction.participantId.value == participant) {
        sibling = view;
        break;
      }
    }
    if (sibling == null) {
      return null;
    }
    final List<FixturePredictionView> next = <FixturePredictionView>[
      for (final FixturePredictionView view in held)
        if (view.prediction.id.value != prediction.id.value) view,
      FixturePredictionView(
        prediction: prediction,
        submittedAt: submittedAt,
        seasonId: sibling.seasonId,
      ),
    ];
    next.sort((FixturePredictionView a, FixturePredictionView b) {
      final int byTime = b.submittedAt.compareTo(a.submittedAt);
      return byTime != 0
          ? byTime
          : a.prediction.id.value.compareTo(b.prediction.id.value);
    });
    return next;
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final Result<void> result = await _inner.save(prediction, submittedAt);
    _afterWrite(prediction, submittedAt, result);
    return result;
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final Result<void> result = await _inner.update(prediction, submittedAt);
    _afterWrite(prediction, submittedAt, result);
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
