import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/read_coalescer.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// An in-process cache in front of the matches screen's win-share split,
/// held per fixture.
///
/// The split is the same for every user looking at the same fixtures, and it
/// moves only as predictions arrive. Each fixture's tally is held on its own
/// (a fixture nobody predicted too), so a batch reads only the fixtures not
/// held, and reads that arrive while the same fixtures load share that load
/// ([ReadCoalescer]). Script 155: the feed read the split of the whole month
/// again every 30 seconds (1078 reads of about 322 rows each in the day and
/// a half after script 141, while the Supabase egress quota was exceeded).
///
/// Every prediction is written through `CachedPredictionHistory`, which
/// calls [forgetFixture] for the fixture it wrote, so a new or amended
/// prediction moves the split on the next read; a merge of two copies of a
/// match calls [forget]. [ttl] only bounds a change made outside this server.
final class CachedFixturePredictionTallyReader
    implements FixturePredictionTallyReader {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedFixturePredictionTallyReader(
    this._inner, {
    Duration ttl = const Duration(minutes: 30),
    int maxEntries = 4096,
    DateTime Function() now = DateTime.now,
  }) : _held = TtlCache<String, _Held>(
         ttl: ttl,
         maxEntries: maxEntries,
         now: now,
       );

  final FixturePredictionTallyReader _inner;

  /// One entry per fixture id, in lower case (the database's form).
  final TtlCache<String, _Held> _held;
  final ReadCoalescer<String, Result<List<FixtureOutcomeTally>>> _loads =
      ReadCoalescer<String, Result<List<FixtureOutcomeTally>>>();

  /// Drops [fixture]'s tally: a prediction on it was written.
  void forgetFixture(FixtureRef fixture) =>
      _held.remove(fixture.value.toLowerCase());

  /// Drops every tally: predictions moved between fixtures (a merge).
  void forget() => _held.clear();

  @override
  Future<Result<List<FixtureOutcomeTally>>> tallyByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    if (fixtures.isEmpty) {
      return _inner.tallyByFixtures(fixtures);
    }
    // Each fixture once, in the order asked; a fixture nobody predicted is
    // omitted, as the database read omits it.
    final List<String> order = <String>[];
    final Map<String, FixtureOutcomeTally?> found =
        <String, FixtureOutcomeTally?>{};
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
        found[id] = held.tally;
      }
    }
    if (missing.isNotEmpty) {
      final List<String> ids = missing.keys.toList()..sort();
      final int startedAt = _held.generation;
      final Result<List<FixtureOutcomeTally>> loaded = await _loads.run(
        '$startedAt|${ids.join(',')}',
        () async {
          final Result<List<FixtureOutcomeTally>> read = await _inner
              .tallyByFixtures(<FixtureRef>[
                for (final String id in ids) missing[id]!,
              ]);
          if (read case Ok<List<FixtureOutcomeTally>>(:final value)) {
            final Map<String, FixtureOutcomeTally> byId =
                <String, FixtureOutcomeTally>{
                  for (final FixtureOutcomeTally tally in value)
                    tally.fixture.value.toLowerCase(): tally,
                };
            for (final String id in ids) {
              _held.write(id, _Held(byId[id]), startedAt: startedAt);
            }
          }
          return read;
        },
      );
      if (loaded case Err<List<FixtureOutcomeTally>>(:final error)) {
        return Result.err(error);
      }
      for (final FixtureOutcomeTally tally
          in (loaded as Ok<List<FixtureOutcomeTally>>).value) {
        found[tally.fixture.value.toLowerCase()] = tally;
      }
    }
    return Result.ok(<FixtureOutcomeTally>[
      for (final String id in order)
        if (found[id] case final FixtureOutcomeTally tally) tally,
    ]);
  }
}

/// A fixture's tally as read, `null` when nobody predicted it.
final class _Held {
  const _Held(this.tally);

  final FixtureOutcomeTally? tally;
}
