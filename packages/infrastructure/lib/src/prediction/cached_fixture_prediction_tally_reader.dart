import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the matches screen's win-share split.
///
/// The split is the same for every user looking at the same fixtures, and it
/// moves only as predictions arrive, so a percentage up to [ttl] old is
/// indistinguishable to a reader. One grouped query then serves every open
/// of the screen inside that window.
final class CachedFixturePredictionTallyReader
    implements FixturePredictionTallyReader {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixturePredictionTallyReader(
    this._inner, {
    Duration ttl = const Duration(seconds: 30),
    int maxEntries = 64,
    DateTime Function() now = DateTime.now,
  }) : _tallies = TtlCache<String, List<FixtureOutcomeTally>>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixturePredictionTallyReader _inner;
  final TtlCache<String, List<FixtureOutcomeTally>> _tallies;

  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    final String key =
        (fixtures.map((fixture) => fixture.value).toList()..sort()).join(',');
    final List<FixtureOutcomeTally>? cached = _tallies.read(key);
    if (cached != null) {
      return Result.ok(cached);
    }
    final int startedAt = _tallies.generation;
    final Result<List<FixtureOutcomeTally>> result = await _inner
        .tallyByFixtures(fixtures);
    if (result case Ok<List<FixtureOutcomeTally>>(:final value)) {
      _tallies.write(key, value, startedAt: startedAt);
    }
    return result;
  }
}
