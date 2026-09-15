import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Short-lived, in-process caches in front of the two leaderboard sums.
///
/// Standings only change when a result is scored, yet every open of the
/// leaderboard tab asked the database to re-sum them. Holding a successful
/// answer for a few seconds turns a burst of opens into one query. Failures
/// are never cached, so a transient error is retried on the next open. The
/// price is that a freshly scored result can take up to [ttl] to show.
///
/// The cache lives in this server process only; it is a performance layer,
/// never a source of truth.
final class _TtlCache<K, V> {
  _TtlCache({
    required this.ttl,
    required this.maxEntries,
    required DateTime Function() now,
  }) : _now = now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;
  final Map<K, (DateTime, V)> _entries = <K, (DateTime, V)>{};

  V? read(K key) {
    final hit = _entries[key];
    if (hit == null) {
      return null;
    }
    if (_now().difference(hit.$1) >= ttl) {
      _entries.remove(key);
      return null;
    }
    return hit.$2;
  }

  void write(K key, V value) {
    _entries.remove(key);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = (_now(), value);
  }
}

/// Caches [FixtureTotalsReader] answers per exact fixture set (the month
/// board and each day board are different sets, so they never collide).
final class CachedFixtureTotalsReader implements FixtureTotalsReader {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixtureTotalsReader(
    this._inner, {
    Duration ttl = const Duration(seconds: 30),
    int maxEntries = 64,
    DateTime Function() now = DateTime.now,
  }) : _cache = _TtlCache<String, List<ParticipantFixtureTotals>>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixtureTotalsReader _inner;
  final _TtlCache<String, List<ParticipantFixtureTotals>> _cache;

  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async {
    final key = (fixtures.map((fixture) => fixture.value).toList()..sort())
        .join(',');
    final cached = _cache.read(key);
    if (cached != null) {
      return Result.ok(cached);
    }
    final result = await _inner.totalsFor(fixtures);
    if (result is Ok<List<ParticipantFixtureTotals>>) {
      _cache.write(key, result.value);
    }
    return result;
  }
}

/// Caches [SportingSeasonStandingsReader] answers per season.
final class CachedSportingSeasonStandingsReader
    implements SportingSeasonStandingsReader {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedSportingSeasonStandingsReader(
    this._inner, {
    Duration ttl = const Duration(seconds: 60),
    DateTime Function() now = DateTime.now,
  }) : _cache = _TtlCache<int, List<SportingSeasonStanding>>(
         ttl: ttl,
         maxEntries: 4,
         now: now,
       );

  final SportingSeasonStandingsReader _inner;
  final _TtlCache<int, List<SportingSeasonStanding>> _cache;

  @override
  Future<Result<List<SportingSeasonStanding>>> standings(
    SportingSeason season,
  ) async {
    final cached = _cache.read(season.startYear);
    if (cached != null) {
      return Result.ok(cached);
    }
    final result = await _inner.standings(season);
    if (result is Ok<List<SportingSeasonStanding>>) {
      _cache.write(season.startYear, result.value);
    }
    return result;
  }
}
