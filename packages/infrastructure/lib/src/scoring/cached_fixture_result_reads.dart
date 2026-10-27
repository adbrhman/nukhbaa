import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the result reads the players' screens
/// make, held per fixture: one fixture's recorded score beside its points
/// (`GET .../fixtures/{id}/scores`), the day board's results
/// (`GET .../predictions-board`) and the month's feed
/// (`GET /feed/current-month-fixtures`).
///
/// A result is the same for every player, yet each card asked the database
/// for it on its own; when a match ended every open screen asked at once.
/// Concurrent reads of the same fixtures share one query ([ReadCoalescer]),
/// and each fixture's answer -- "no result yet" included -- is held on its
/// own, so a batch reads only the fixtures not held (script 155: the feed
/// read the whole month's results again every 20 seconds, 1641 reads of
/// about 217 rows each in the day and a half after script 141, while the
/// Supabase egress quota was exceeded). Failures are never cached.
///
/// Every result is written through [upsert] here (`RecordFixtureResult`,
/// the admin's form and the provider sync alike, is handed this decorator),
/// which drops that fixture, so a new or corrected result shows on the next
/// read. [ttl] only bounds an edit made outside this server. Scoring keeps
/// the plain repository: it reads the database directly.
final class CachedFixtureResultReads implements FixtureResultRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixtureResultReads(
    this._inner, {
    Duration ttl = const Duration(minutes: 30),
    int maxEntries = 4096,
    DateTime Function() now = DateTime.now,
  }) : _held = TtlCache<String, _Found>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixtureResultRepository _inner;

  /// One entry per fixture id, in lower case (the database's form).
  final TtlCache<String, _Found> _held;
  final ReadCoalescer<String, Result<FixtureResult?>> _singleLoads =
      ReadCoalescer<String, Result<FixtureResult?>>();
  final ReadCoalescer<String, Result<List<FixtureResult>>> _batchLoads =
      ReadCoalescer<String, Result<List<FixtureResult>>>();

  @override
  Future<Result<void>> upsert(FixtureResult result, DateTime recordedAt) async {
    final Result<void> written = await _inner.upsert(result, recordedAt);
    // Dropped on failure too: a write that errored may still have landed.
    _held.remove(result.fixture.value.toLowerCase());
    return written;
  }

  /// Drops every held answer.
  void forget() => _held.clear();

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) {
    final String id = fixture.value.toLowerCase();
    final _Found? cached = _held.read(id);
    if (cached != null) {
      return Future<Result<FixtureResult?>>.value(
        Result<FixtureResult?>.ok(cached.result),
      );
    }
    final int startedAt = _held.generation;
    return _singleLoads.run('$startedAt|$id', () async {
      final Result<FixtureResult?> found = await _inner.findByFixture(fixture);
      if (found case Ok<FixtureResult?>(:final value)) {
        _held.write(id, _Found(value), startedAt: startedAt);
      }
      return found;
    });
  }

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    if (fixtures.isEmpty) {
      return _inner.findByFixtures(fixtures);
    }
    // Each fixture once, in the order asked; fixtures without a result are
    // omitted, as the database read omits them.
    final List<String> order = <String>[];
    final Map<String, FixtureResult?> found = <String, FixtureResult?>{};
    final Map<String, FixtureRef> missing = <String, FixtureRef>{};
    for (final FixtureRef fixture in fixtures) {
      final String id = fixture.value.toLowerCase();
      if (found.containsKey(id) || missing.containsKey(id)) {
        continue;
      }
      order.add(id);
      final _Found? held = _held.read(id);
      if (held == null) {
        missing[id] = fixture;
      } else {
        found[id] = held.result;
      }
    }
    if (missing.isNotEmpty) {
      final List<String> ids = missing.keys.toList()..sort();
      final int startedAt = _held.generation;
      final Result<List<FixtureResult>> loaded = await _batchLoads.run(
        '$startedAt|${ids.join(',')}',
        () async {
          final Result<List<FixtureResult>> read = await _inner.findByFixtures(
            <FixtureRef>[for (final String id in ids) missing[id]!],
          );
          if (read case Ok<List<FixtureResult>>(:final value)) {
            final Map<String, FixtureResult> byId = <String, FixtureResult>{
              for (final FixtureResult result in value)
                result.fixture.value.toLowerCase(): result,
            };
            for (final String id in ids) {
              _held.write(id, _Found(byId[id]), startedAt: startedAt);
            }
          }
          return read;
        },
      );
      if (loaded case Err<List<FixtureResult>>(:final error)) {
        return Result.err(error);
      }
      for (final FixtureResult result
          in (loaded as Ok<List<FixtureResult>>).value) {
        found[result.fixture.value.toLowerCase()] = result;
      }
    }
    return Result.ok(<FixtureResult>[
      for (final String id in order)
        if (found[id] case final FixtureResult result) result,
    ]);
  }
}

/// A stored answer for one fixture, so "no result yet" (`null`) can be
/// held as well.
final class _Found {
  const _Found(this.result);

  final FixtureResult? result;
}
