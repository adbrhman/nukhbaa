import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the team catalog.
///
/// The catalog is seed data that changes with a migration, not with use, yet
/// the whole table was read on every `GET /teams` and every admin form that
/// lists clubs. Nothing in the application writes it, so [ttl] is the only
/// bound on how long a newly seeded club takes to appear.
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

  @override
  Future<Result<List<Team>>> listAll() async {
    final List<Team>? cached = _all.read(_key);
    if (cached != null) {
      return Result.ok(cached);
    }
    final int startedAt = _all.generation;
    final Result<List<Team>> result = await _inner.listAll();
    if (result case Ok<List<Team>>(:final value)) {
      _all.write(_key, value, startedAt: startedAt);
    }
    return result;
  }
}
