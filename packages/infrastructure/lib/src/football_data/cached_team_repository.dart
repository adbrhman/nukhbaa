import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the team catalog.
///
/// The catalog is seed data that changes with a migration, not with use, yet
/// the whole table was read on every `GET /teams` and every admin form that
/// lists clubs. A club an admin adds (script 91) goes through
/// [CacheClearingTeamCatalogWriter], which calls [invalidate]; [ttl] bounds
/// how long a newly seeded club takes to appear.
final class CachedTeamRepository implements TeamRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedTeamRepository(
    this._inner, {
    Duration ttl = const Duration(minutes: 10),
    DateTime Function() now = DateTime.now,
  }) : _all = TtlCache<int, List<Team>>(ttl: ttl, maxEntries: 1, now: now);

  static const int _key = 0;

  final TeamRepository _inner;
  final TtlCache<int, List<Team>> _all;
  final ReadCoalescer<int, Result<List<Team>>> _loads =
      ReadCoalescer<int, Result<List<Team>>>();

  /// Forgets the cached catalog, and any read still in flight, so the next
  /// [listAll] reads the table again.
  void invalidate() => _all.clear();

  @override
  Future<Result<List<Team>>> listAll() async {
    final List<Team>? cached = _all.read(_key);
    if (cached != null) {
      return Result.ok(cached);
    }
    final int startedAt = _all.generation;
    return _loads.run(startedAt, () async {
      final Result<List<Team>> result = await _inner.listAll();
      if (result case Ok<List<Team>>(:final value)) {
        _all.write(_key, value, startedAt: startedAt);
      }
      return result;
    });
  }
}

/// Adds clubs through [_inner], then empties [_cache], so the next
/// `GET /teams` carries the club just added instead of waiting out the
/// cache's ttl (script 91). The cache lives in this server process only.
final class CacheClearingTeamCatalogWriter implements TeamCatalogWriter {
  /// Wraps [_inner] in front of [_cache].
  const CacheClearingTeamCatalogWriter(this._inner, this._cache);

  final TeamCatalogWriter _inner;
  final CachedTeamRepository _cache;

  @override
  Future<Result<TeamAddition>> add({
    required String name,
    required LeagueRef? leagueId,
  }) async {
    final Result<TeamAddition> result = await _inner.add(
      name: name,
      leagueId: leagueId,
    );
    if (result case Ok<TeamAddition>(:final value) when !value.existed) {
      _cache.invalidate();
    }
    return result;
  }
}
