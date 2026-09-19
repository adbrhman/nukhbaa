import 'dart:async';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// First fixtures sync after boot: also covers today.
const Duration providerFixturesFirstRunDelay = Duration(minutes: 3);

/// Later fixtures syncs: the next two Riyadh days, once a day. A day is seen
/// twice before it arrives, so a late schedule change is still picked up.
const Duration providerFixturesTick = Duration(hours: 24);

/// Results checks. Each run only calls the provider when a synced fixture is
/// due, so most runs cost nothing.
const Duration providerResultsTick = Duration(minutes: 10);

/// Live-score polls. Each run only calls a provider while a synced fixture
/// of one of its competitions is in play.
const Duration providerLiveTick = Duration(minutes: 2);

/// Drives the automatic fixtures/results sync in the server process, like the
/// reminder sweep: in-process timers, never awaited, failures logged and
/// retried on the next tick. Does nothing when the mode is `off` or no
/// provider key is configured.
void startProviderSyncScheduler(CompositionRoot root) {
  final mode = root.providerSyncMode;
  final fixtures = root.syncProviderFixtures;
  final results = root.syncProviderResults;
  if (mode == ProviderSyncMode.off || fixtures == null || results == null) {
    _log('off', 'provider sync is off');
    return;
  }
  final apply = mode == ProviderSyncMode.on;
  final tag = mode.name;
  var fixturesRunning = false;
  var resultsRunning = false;

  Future<void> runFixtures({required bool includeToday}) async {
    if (fixturesRunning) return;
    fixturesRunning = true;
    try {
      final now = DateTime.now().toUtc();
      final today = riyadhDayOf(now);
      final days = <DateTime>[
        if (includeToday) today,
        DateTime.utc(today.year, today.month, today.day + 1),
        DateTime.utc(today.year, today.month, today.day + 2),
      ];
      final report = await fixtures(now: now, riyadhDays: days, apply: apply);
      _report(tag, 'fixtures', report);
    } on Object catch (error) {
      _log(tag, 'fixtures sync threw: $error');
    } finally {
      fixturesRunning = false;
    }
  }

  Future<void> runResults() async {
    if (resultsRunning) return;
    resultsRunning = true;
    try {
      final report = await results(now: DateTime.now().toUtc(), apply: apply);
      _report(tag, 'results', report);
    } on Object catch (error) {
      _log(tag, 'results sync threw: $error');
    } finally {
      resultsRunning = false;
    }
  }

  final live = root.refreshLiveScores;
  var liveRunning = false;
  Future<void> runLive() async {
    if (live == null || liveRunning) return;
    liveRunning = true;
    try {
      final result = await live(now: DateTime.now().toUtc());
      switch (result) {
        case Err<LiveScoreRefresh>(:final error):
          _log(tag, 'live scores failed: ${error.code} ${error.message}');
        case Ok<LiveScoreRefresh>(:final value):
          // Full time seen by the 2-minute live poll: check results now
          // instead of waiting for the next results tick. The score is still
          // recorded only after it has stood unchanged for the confirmation
          // time (SyncProviderResults.confirmAfter).
          if (value.finished.isNotEmpty) {
            _log(tag, 'full time on ${value.finished.length} fixture(s)');
            unawaited(runResults());
          }
      }
    } on Object catch (error) {
      _log(tag, 'live scores threw: $error');
    } finally {
      liveRunning = false;
    }
  }

  _log(tag, 'provider sync started');
  if (live != null) {
    Timer.periodic(providerLiveTick, (_) {
      unawaited(runLive());
    });
  }
  Timer(providerFixturesFirstRunDelay, () {
    unawaited(runFixtures(includeToday: true));
  });
  Timer.periodic(providerFixturesTick, (_) {
    unawaited(runFixtures(includeToday: false));
  });
  Timer.periodic(providerResultsTick, (_) {
    unawaited(runResults());
  });
}

void _report(String tag, String job, Result<ProviderSyncReport> result) {
  switch (result) {
    case Ok<ProviderSyncReport>(:final value):
      if (value.requests == 0 && value.notes.isEmpty) return;
      _log(
        tag,
        '$job: requests=${value.requests} applied=${value.applied} '
        'known=${value.alreadyKnown} skipped=${value.skipped}',
      );
      for (final note in value.notes) {
        _log(tag, '  $note');
      }
    case Err<ProviderSyncReport>(:final error):
      _log(tag, '$job failed: ${error.code} ${error.message}');
  }
}

void _log(String tag, String message) {
  // ignore: avoid_print
  print('provider-sync [$tag] $message');
}
