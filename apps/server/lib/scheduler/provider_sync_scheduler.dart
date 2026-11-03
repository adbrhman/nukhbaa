import 'dart:async';
import 'dart:io';

import 'package:application/application.dart';
import 'package:meta/meta.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// First fixtures sync after boot: also covers today.
const Duration providerFixturesFirstRunDelay = Duration(minutes: 3);

/// Later fixtures syncs: today and the next two Riyadh days, twice a day.
/// Today is included so a kickoff moved on match day reaches the schedule
/// (C-03); Highlightly, capped at two days, then sees today and tomorrow.
const Duration providerFixturesTick = Duration(hours: 12);

/// The Riyadh clock times of the fixtures syncs after the first (script
/// 190): 00:05 and 12:05, no longer 12 hours from each boot. The run at
/// 00:05 is the first of the day before a day, so the daily selection's
/// check of that day, and the owner's alert, come 24 hours ahead of it.
const List<Duration> providerFixturesAnchors = <Duration>[
  Duration(minutes: 5),
  Duration(hours: 12, minutes: 5),
];

/// How long from [nowUtc] until the next [providerFixturesAnchors] time on
/// the Riyadh clock (UTC+3, no daylight saving).
Duration untilNextFixturesRun(DateTime nowUtc) {
  final riyadh = nowUtc.toUtc().add(const Duration(hours: 3));
  final midnight = DateTime.utc(riyadh.year, riyadh.month, riyadh.day);
  for (var days = 0; days < 2; days++) {
    for (final anchor in providerFixturesAnchors) {
      final at = DateTime.utc(
        midnight.year,
        midnight.month,
        midnight.day + days,
      ).add(anchor);
      if (at.isAfter(riyadh)) {
        return at.difference(riyadh);
      }
    }
  }
  return providerFixturesTick;
}

/// Whether the fixtures syncs run at [providerFixturesAnchors] (script 191):
/// only once the daily selection adds matches (`NUKHBA_DAILY_MINIMUM=on`).
/// The trial and `off` keep a sync every 12 hours from boot, as before, so
/// the trial changes nothing the players get.
bool fixturesAtFixedTimes(Map<String, String> env) =>
    DailySelectionMode.parse(env['NUKHBA_DAILY_MINIMUM']) ==
    DailySelectionMode.on;

/// Results checks. Each run only calls the provider when a synced fixture is
/// due, so most runs cost nothing.
const Duration providerResultsTick = Duration(minutes: 10);

/// Live-score polls. Each run only calls a provider while a synced fixture
/// of one of its competitions is in play.
const Duration providerLiveTick = Duration(minutes: 2);

/// Match details reads (script 118). Each run only calls the provider for
/// finished matches still without details, a few a run.
const Duration matchDetailsTick = Duration(minutes: 30);

/// First match details read after boot. Without it every restart put the
/// first read off by a whole [matchDetailsTick]: nothing was read in the
/// hour after script 118 went out (2026-10-19).
const Duration matchDetailsFirstRunDelay = Duration(minutes: 5);

/// Drives the automatic fixtures/results sync in the server process, like the
/// reminder sweep: in-process timers, never awaited, failures logged and
/// retried on the next tick. Does nothing when the mode is `off` or no
/// provider key is configured.
///
/// Each of the four syncs runs through [singleFlight], like every other
/// sweep, so the [drainSweeps] a SIGTERM awaits waits for a sync in
/// progress and starts none after it (audit 13: M-28 had left these
/// out). Their times are unchanged.
void startProviderSyncScheduler(CompositionRoot root) =>
    scheduleProviderSync(root);

/// [startProviderSyncScheduler] with its timers made by [once] and
/// [every], as [phasedPeriodic]'s are, so a test can fire a tick itself.
@visibleForTesting
void scheduleProviderSync(
  CompositionRoot root, {
  OneShotTimerFactory once = Timer.new,
  PeriodicTimerFactory every = Timer.periodic,
}) {
  final mode = root.providerSyncMode;
  final fixtures = root.syncProviderFixtures;
  final results = root.syncProviderResults;
  if (mode == ProviderSyncMode.off || fixtures == null || results == null) {
    _log('off', 'provider sync is off');
    return;
  }
  final apply = mode == ProviderSyncMode.on;
  final tag = mode.name;

  // Every sync below runs through singleFlight (audit 13): a tick that
  // finds its sync still running is skipped, and drainSweeps waits for it.
  final fixturesFlight = singleFlight<bool>((includeToday) async {
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
      if (apply) {
        await _askAdmins(root, 'provider-sync fixtures', report);
      }
      if (report case Err<ProviderSyncReport>(:final error)) {
        await reportJobFailure(
          root,
          job: 'provider-sync fixtures',
          error: error,
        );
      }
    } on Object catch (error, stackTrace) {
      _log(tag, 'fixtures sync threw: $error');
      await reportJobFailure(
        root,
        job: 'provider-sync fixtures',
        error: error,
        stackTrace: stackTrace,
      );
    }
  });
  Future<void> runFixtures({required bool includeToday}) =>
      fixturesFlight(includeToday);

  final resultsFlight = singleFlight<CompositionRoot>((_) async {
    try {
      final report = await results(now: DateTime.now().toUtc(), apply: apply);
      _report(tag, 'results', report);
      if (apply) {
        await _askAdmins(root, 'provider-sync results', report);
      }
      if (report case Err<ProviderSyncReport>(:final error)) {
        await reportJobFailure(
          root,
          job: 'provider-sync results',
          error: error,
          critical: true,
        );
      }
    } on Object catch (error, stackTrace) {
      _log(tag, 'results sync threw: $error');
      await reportJobFailure(
        root,
        job: 'provider-sync results',
        error: error,
        stackTrace: stackTrace,
        critical: true,
      );
    }
  });
  Future<void> runResults() => resultsFlight(root);

  final live = root.refreshLiveScores;
  final liveFlight = singleFlight<CompositionRoot>((_) async {
    if (live == null) return;
    try {
      final result = await live(now: DateTime.now().toUtc());
      switch (result) {
        case Err<LiveScoreRefresh>(:final error):
          _log(tag, 'live scores failed: ${error.code} ${error.message}');
          await reportJobFailure(root, job: 'provider-sync live', error: error);
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
    } on Object catch (error, stackTrace) {
      _log(tag, 'live scores threw: $error');
      await reportJobFailure(
        root,
        job: 'provider-sync live',
        error: error,
        stackTrace: stackTrace,
      );
    }
  });
  Future<void> runLive() => liveFlight(root);

  // The story of each finished match (script 118). Shadow mode writes
  // nothing, so it reads nothing either.
  final details = apply ? root.syncMatchDetails : null;
  final detailsFlight = singleFlight<CompositionRoot>((_) async {
    if (details == null) return;
    try {
      final result = await details(now: DateTime.now().toUtc());
      switch (result) {
        case Err<MatchDetailsReport>(:final error):
          _log(tag, 'match details failed: ${error.code} ${error.message}');
          await reportJobFailure(
            root,
            job: 'provider-sync match details',
            error: error,
          );
        case Ok<MatchDetailsReport>(:final value):
          if (value.pending > 0 || value.notes.isNotEmpty) {
            _log(
              tag,
              'match details: pending=${value.pending} '
              'requests=${value.requests} '
              'saved=${value.saved} not_found=${value.notFound} '
              'out_of_scope=${value.outOfScope}',
            );
            for (final note in value.notes) {
              _log(tag, '  $note');
            }
          }
      }
    } on Object catch (error, stackTrace) {
      _log(tag, 'match details threw: $error');
      await reportJobFailure(
        root,
        job: 'provider-sync match details',
        error: error,
        stackTrace: stackTrace,
      );
    }
  });
  Future<void> runDetails() => detailsFlight(root);

  _log(tag, 'provider sync started');
  if (details != null) {
    once(matchDetailsFirstRunDelay, () {
      unawaited(runDetails());
    });
    phasedPeriodic(
      matchDetailsPhase,
      matchDetailsTick,
      (_) {
        unawaited(runDetails());
      },
      once: once,
      every: every,
    );
  }
  if (live != null) {
    phasedPeriodic(
      providerLivePhase,
      providerLiveTick,
      (_) {
        unawaited(runLive());
      },
      once: once,
      every: every,
    );
  }
  once(providerFixturesFirstRunDelay, () {
    unawaited(runFixtures(includeToday: true));
  });
  // At fixed Riyadh times (script 190), each run setting the next.
  void scheduleFixtures() {
    final wait =
        untilNextFixturesRun(DateTime.now().toUtc()) + providerFixturesPhase;
    once(wait, () {
      unawaited(runFixtures(includeToday: true));
      scheduleFixtures();
    });
  }

  if (fixturesAtFixedTimes(Platform.environment)) {
    scheduleFixtures();
  } else {
    // The trial or off (script 191): every 12 hours from boot, as before.
    phasedPeriodic(
      providerFixturesPhase,
      providerFixturesTick,
      (_) {
        unawaited(runFixtures(includeToday: true));
      },
      once: once,
      every: every,
    );
  }
  phasedPeriodic(
    providerResultsPhase,
    providerResultsTick,
    (_) {
      unawaited(runResults());
    },
    once: once,
    every: every,
  );
}

/// Keeps every match a run left for an admin in the error log, which tells
/// the admins (audit C-03): before this they were lines in the container
/// log nobody reads. Shadow runs only print them.
Future<void> _askAdmins(
  CompositionRoot root,
  String job,
  Result<ProviderSyncReport> result,
) async {
  if (result case Ok<ProviderSyncReport>(:final value)) {
    for (final item in value.attention) {
      await reportNeedsAdmin(
        root,
        job: job,
        subject: item.match,
        code: item.code,
        message: item.message,
      );
    }
  }
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
