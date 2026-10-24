import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the batched schedule read, held per
/// fixture.
///
/// Every open of the matches screen asks for the schedules of the same
/// month's fixtures, so one answer can serve every user for [ttl]. Each
/// fixture's schedule is held on its own (a fixture with no schedule too),
/// so a batch reads only the fixtures not held yet: a player's history that
/// grew by one prediction reads one schedule, and players who predicted the
/// same fixtures share each read (script 141; a batch used to be held whole,
/// under the sorted list of its fixtures, so one new fixture read every
/// schedule of the history again: 5320 reads, 748 thousand of the widest
/// rows, in the day and a half after script 138). Each schedule write
/// (register, correct, provider sync) goes through [upsert] here and drops
/// the whole cache, so a changed kickoff shows on the next read. Reads that
/// arrive while the same fixtures are loading share that load
/// ([ReadCoalescer]): a provider sync drops the whole cache.
final class CachedFixtureScheduleRepository
    implements FixtureScheduleRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixtureScheduleRepository(
    this._inner, {
    Duration ttl = const Duration(seconds: 60),
    int maxEntries = 4096,
    DateTime Function() now = DateTime.now,
  }) : _held = TtlCache<String, _Held>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixtureScheduleRepository _inner;

  /// One entry per fixture id, in lower case (the database's form).
  final TtlCache<String, _Held> _held;
  final ReadCoalescer<String, Result<List<FixtureSchedule>>> _loads =
      ReadCoalescer<String, Result<List<FixtureSchedule>>>();

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async {
    final Result<void> result = await _inner.upsert(schedule);
    // Cleared on failure too: a write that errored may still have landed.
    _held.clear();
    return result;
  }

  /// Drops every cached answer: a fixture was hidden or shown (migration
  /// 0098), a change that does not go through [upsert].
  void forget() => _held.clear();

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
    // Each fixture once, in the order asked; absent ones are omitted, as
    // the database read omits them.
    final List<String> order = <String>[];
    final Map<String, FixtureSchedule?> found = <String, FixtureSchedule?>{};
    final Map<String, FixtureRef> missing = <String, FixtureRef>{};
    for (final FixtureRef fixture in fixtures) {
      final String id = fixture.value.toLowerCase();
      if (found.containsKey(id) || missing.containsKey(id)) {
        continue;
      }
      order.add(id);
      final _Held? held = _held.read(id);
      if (held == null) {
        missing[id] = fixture;
      } else {
        found[id] = held.schedule;
      }
    }
    if (missing.isNotEmpty) {
      final List<String> ids = missing.keys.toList()..sort();
      final int startedAt = _held.generation;
      final Result<List<FixtureSchedule>> loaded = await _loads.run(
        '$startedAt|${ids.join(',')}',
        () async {
          final Result<List<FixtureSchedule>> read = await _inner
              .findByFixtures(<FixtureRef>[
                for (final String id in ids) missing[id]!,
              ]);
          if (read case Ok<List<FixtureSchedule>>(:final value)) {
            final Map<String, FixtureSchedule> byId = <String, FixtureSchedule>{
              for (final FixtureSchedule schedule in value)
                schedule.fixture.value.toLowerCase(): schedule,
            };
            for (final String id in ids) {
              _held.write(id, _Held(byId[id]), startedAt: startedAt);
            }
          }
          return read;
        },
      );
      if (loaded case Err<List<FixtureSchedule>>(:final error)) {
        return Result.err(error);
      }
      for (final FixtureSchedule schedule
          in (loaded as Ok<List<FixtureSchedule>>).value) {
        found[schedule.fixture.value.toLowerCase()] = schedule;
      }
    }
    return Result.ok(<FixtureSchedule>[
      for (final String id in order)
        if (found[id] case final FixtureSchedule schedule) schedule,
    ]);
  }
}

/// A fixture's schedule as read, `null` when the fixture has none.
final class _Held {
  const _Held(this.schedule);

  final FixtureSchedule? schedule;
}
