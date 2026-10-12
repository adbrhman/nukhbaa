import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// Short-lived, in-process caches in front of the result reads the players'
/// screens make: one fixture's recorded score beside its points
/// (`GET .../fixtures/{id}/scores`) and the day board's results
/// (`GET .../predictions-board`).
///
/// A result is the same for every player, yet each card asked the database
/// for it on its own; when a match ended every open screen asked at once.
/// Concurrent reads of the same answer share one query ([ReadCoalescer]),
/// and a successful answer -- "no result yet" included -- serves every
/// request for [ttl]. Failures are never cached.
///
/// Wired into the read use-cases only, never into scoring or the admin
/// result form: those must see a result the moment it is written, and a
/// result recorded by the provider sync does not pass through here. So a
/// new result takes up to [ttl] to show on these screens; [upsert] still
/// drops everything should a writer ever be handed this decorator.
final class CachedFixtureResultReads implements FixtureResultRepository {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixtureResultReads(
    this._inner, {
    Duration ttl = const Duration(seconds: 20),
    int maxEntries = 512,
    DateTime Function() now = DateTime.now,
  }) : _single = TtlCache<String, _Found>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       ),
       _batches = TtlCache<String, List<FixtureResult>>(
         ttl: ttl,
         maxEntries: 64,
         now: now,
       );

  final FixtureResultRepository _inner;
  final TtlCache<String, _Found> _single;
  final TtlCache<String, List<FixtureResult>> _batches;
  final ReadCoalescer<String, Result<FixtureResult?>> _singleLoads =
      ReadCoalescer<String, Result<FixtureResult?>>();
  final ReadCoalescer<String, Result<List<FixtureResult>>> _batchLoads =
      ReadCoalescer<String, Result<List<FixtureResult>>>();

  @override
  Future<Result<void>> upsert(FixtureResult result, DateTime recordedAt) async {
    final Result<void> written = await _inner.upsert(result, recordedAt);
    // Cleared on failure too: a write that errored may still have landed.
    _single.clear();
    _batches.clear();
    return written;
  }

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) {
    final _Found? cached = _single.read(fixture.value);
    if (cached != null) {
      return Future<Result<FixtureResult?>>.value(
        Result<FixtureResult?>.ok(cached.result),
      );
    }
    final int startedAt = _single.generation;
    return _singleLoads.run('$startedAt|${fixture.value}', () async {
      final Result<FixtureResult?> found = await _inner.findByFixture(fixture);
      if (found case Ok<FixtureResult?>(:final value)) {
        _single.write(fixture.value, _Found(value), startedAt: startedAt);
      }
      return found;
    });
  }

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) {
    if (fixtures.isEmpty) {
      return _inner.findByFixtures(fixtures);
    }
    final String key =
        (fixtures.map((fixture) => fixture.value).toList()..sort()).join(',');
    final List<FixtureResult>? cached = _batches.read(key);
    if (cached != null) {
      return Future<Result<List<FixtureResult>>>.value(
        Result<List<FixtureResult>>.ok(cached),
      );
    }
    final int startedAt = _batches.generation;
    return _batchLoads.run('$startedAt|$key', () async {
      final Result<List<FixtureResult>> found = await _inner.findByFixtures(
        fixtures,
      );
      if (found case Ok<List<FixtureResult>>(:final value)) {
        _batches.write(key, value, startedAt: startedAt);
      }
      return found;
    });
  }
}

/// A stored answer of [CachedFixtureResultReads.findByFixture], so "no
/// result yet" (`null`) can be cached as well.
final class _Found {
  const _Found(this.result);

  final FixtureResult? result;
}
