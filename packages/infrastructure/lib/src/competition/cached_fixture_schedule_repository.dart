import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the batched schedule read.
///
/// Every open of the matches screen asks for the schedules of the same
/// month's fixtures, so one answer can serve every user for [ttl]. Each
/// schedule write (register, correct, provider sync) goes through [upsert]
/// here and drops the whole cache, so a changed kickoff shows on the next
/// read.
final class CachedFixtureScheduleRepository
    implements FixtureScheduleRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixtureScheduleRepository(
    this._inner, {
    Duration ttl = const Duration(seconds: 60),
    int maxEntries = 64,
    DateTime Function() now = DateTime.now,
  }) : _batches = TtlCache<String, List<FixtureSchedule>>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixtureScheduleRepository _inner;
  final TtlCache<String, List<FixtureSchedule>> _batches;

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async {
    final Result<void> result = await _inner.upsert(schedule);
    // Cleared on failure too: a write that errored may still have landed.
    _batches.clear();
    return result;
  }

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) =>
      _inner.findByFixture(fixture);

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    if (fixtures.isEmpty) {
      return _inner.findByFixtures(fixtures);
    }
    final String key =
        (fixtures.map((fixture) => fixture.value).toList()..sort()).join(',');
    final List<FixtureSchedule>? cached = _batches.read(key);
    if (cached != null) {
      return Result.ok(cached);
    }
    final int startedAt = _batches.generation;
    final Result<List<FixtureSchedule>> result = await _inner.findByFixtures(
      fixtures,
    );
    if (result case Ok<List<FixtureSchedule>>(:final value)) {
      _batches.write(key, value, startedAt: startedAt);
    }
    return result;
  }
}
