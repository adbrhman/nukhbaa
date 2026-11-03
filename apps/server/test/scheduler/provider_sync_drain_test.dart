import 'dart:async';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/provider_sync_scheduler.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// Audit 13: the provider syncs ran outside singleFlight, so the drainSweeps
// a SIGTERM awaits (M-28) neither waited for one in progress nor stopped
// the next. Alone in its file: once drained, no sweep starts again in this
// process.

/// The leagues: the fixtures sync reads them first, and waits here.
final class _Leagues implements LeagueRepository {
  final Completer<Result<List<League>>> gate =
      Completer<Result<List<League>>>();
  int reads = 0;

  @override
  Future<Result<List<League>>> listAll() {
    reads++;
    return gate.future;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The sync store: the results sync asks it first for the fixtures waiting
/// for a result, and waits here.
final class _Store implements ProviderSyncStore {
  final Completer<Result<List<PendingProviderFixture>>> gate =
      Completer<Result<List<PendingProviderFixture>>>();
  int reads = 0;

  @override
  Future<Result<List<PendingProviderFixture>>> fixturesAwaitingResult({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  }) {
    reads++;
    return gate.future;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Provider implements FootballDataProvider {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Teams implements TeamRepository {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Competitions implements CompetitionRepository {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Schedules implements FixtureScheduleRepository {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Predictions implements FixturePredictionRepository {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Ids implements IdGenerator {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A timer that never fires by itself.
final class _Idle implements Timer {
  @override
  bool get isActive => false;

  @override
  int get tick => 0;

  @override
  void cancel() {}
}

/// Keeps the timers the scheduler asks for, so the test fires a tick itself.
final class _Timers {
  final Map<Duration, void Function()> _once = <Duration, void Function()>{};
  final Map<Duration, void Function(Timer)> _every =
      <Duration, void Function(Timer)>{};

  Timer once(Duration duration, void Function() callback) {
    _once[duration] = callback;
    return _Idle();
  }

  Timer every(Duration period, void Function(Timer timer) callback) {
    _every[period] = callback;
    return _Idle();
  }

  void fire(Duration duration) => _once[duration]!();

  void tick(Duration period) => _every[period]!(_Idle());
}

const ProviderLeagueRule _rule = ProviderLeagueRule(
  source: 'test-provider',
  externalLeagueId: '1',
  leagueName: 'Test League',
);

void main() {
  test('a SIGTERM waits for the provider syncs in progress, and starts '
      'none after them', () async {
    final _Leagues leagues = _Leagues();
    final _Store store = _Store();
    final Map<String, FootballDataProvider> providers =
        <String, FootballDataProvider>{'test-provider': _Provider()};
    final CompositionRoot root = CompositionRoot.forTesting(
      providerSyncMode: ProviderSyncMode.shadow,
      syncProviderFixtures: SyncProviderFixtures(
        providers: providers,
        store: store,
        leagueRepository: leagues,
        teamRepository: _Teams(),
        competitionRepository: _Competitions(),
        fixtureScheduleRepository: _Schedules(),
        fixturePredictionRepository: _Predictions(),
        idGenerator: _Ids(),
        rules: const <ProviderLeagueRule>[_rule],
      ),
      syncProviderResults: SyncProviderResults(
        providers: providers,
        store: store,
        leagueRepository: leagues,
        rules: const <ProviderLeagueRule>[_rule],
        recorder:
            ({
              required String fixtureId,
              required int homeGoals,
              required int awayGoals,
            }) async => const Result<void>.ok(null),
      ),
    );
    final _Timers timers = _Timers();
    scheduleProviderSync(root, once: timers.once, every: timers.every);

    // The first fixtures sync, three minutes after boot, and the first
    // results sync, a tick after its phase: both wait on the database.
    timers.fire(providerFixturesFirstRunDelay);
    timers.fire(providerResultsPhase);
    timers.tick(providerResultsTick);
    expect(leagues.reads, 1);
    expect(store.reads, 1);

    bool drained = false;
    final Future<void> drain = drainSweeps().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse, reason: 'two syncs are still running');

    leagues.gate.complete(
      const Result<List<League>>.err(AppError.transient('test.held', 'held')),
    );
    store.gate.complete(
      const Result<List<PendingProviderFixture>>.ok(<PendingProviderFixture>[]),
    );
    await drain;
    expect(drained, isTrue);

    // The next ticks, once the server is stopping, start no sync.
    timers.fire(providerFixturesFirstRunDelay);
    timers.tick(providerResultsTick);
    await Future<void>.delayed(Duration.zero);
    expect(leagues.reads, 1, reason: 'no fixtures sync after the drain');
    expect(store.reads, 1, reason: 'no results sync after the drain');
  });
}
