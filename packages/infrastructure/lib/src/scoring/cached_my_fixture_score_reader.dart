import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of a player's own grades, points and final
/// scores (`GET /me/fixture-scores`, [MyFixtureScoreReader.listByUser]),
/// held per player until a result or a score is written.
///
/// The read lists every scored or finished prediction the player ever made,
/// so it grows every day, and the app reads it again with every feed and
/// history refresh: 1826 reads of about 364 rows each between 25 October
/// and 1 November 2026, with no cache, while the Supabase egress quota was
/// exceeded (script 192).
///
/// A row exists only once its fixture has a result or a score, and both are
/// written through this server alone: `RecordFixtureResult` through
/// `CachedFixtureResultReads` and scoring through
/// `CachedFixtureScoreRepository`, each of which calls [forget]; a merge of
/// two copies of a match calls it too. A prediction itself adds no row (it
/// is written before kickoff, when its fixture has neither). [ttl] only
/// bounds an edit made outside this server. Failures are never cached.
final class CachedMyFixtureScoreReader implements MyFixtureScoreReader {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedMyFixtureScoreReader(
    this._inner, {
    Duration ttl = const Duration(hours: 6),
    int maxEntries = 1024,
    DateTime Function() now = DateTime.now,
  }) : _byUser = TtlCache<String, List<MyFixtureScore>>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final MyFixtureScoreReader _inner;
  final TtlCache<String, List<MyFixtureScore>> _byUser;
  final ReadCoalescer<String, Result<List<MyFixtureScore>>> _loads =
      ReadCoalescer<String, Result<List<MyFixtureScore>>>();

  /// Drops every player's rows: a result or a score was written.
  void forget() => _byUser.clear();

  @override
  Future<Result<List<MyFixtureScore>>> listByUser(UserId userId) {
    final String key = userId.value.toLowerCase();
    final List<MyFixtureScore>? cached = _byUser.read(key);
    if (cached != null) {
      return Future<Result<List<MyFixtureScore>>>.value(
        Result<List<MyFixtureScore>>.ok(cached),
      );
    }
    final int startedAt = _byUser.generation;
    return _loads.run('$startedAt|$key', () async {
      final Result<List<MyFixtureScore>> found = await _inner.listByUser(
        userId,
      );
      if (found case Ok<List<MyFixtureScore>>(:final value)) {
        final List<MyFixtureScore> held = List<MyFixtureScore>.unmodifiable(
          value,
        );
        _byUser.write(key, held, startedAt: startedAt);
        return Result<List<MyFixtureScore>>.ok(held);
      }
      return found;
    });
  }
}
