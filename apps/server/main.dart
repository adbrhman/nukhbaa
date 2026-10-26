import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/badge_evaluation_scheduler.dart';
import 'package:server/scheduler/h2h_league_scheduler.dart';
import 'package:server/scheduler/incomplete_day_scheduler.dart';
import 'package:server/scheduler/match_day_settlement_scheduler.dart';
import 'package:server/scheduler/monthly_season_scheduler.dart';
import 'package:server/scheduler/notification_queue_scheduler.dart';
import 'package:server/scheduler/pre_match_scheduler.dart';
import 'package:server/scheduler/provider_sync_scheduler.dart';
import 'package:server/scheduler/reminder_scheduler.dart';
import 'package:server/scheduler/rescore_scheduler.dart';
import 'package:server/scheduler/scheduler_switch.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:server/scheduler/streak_saver_scheduler.dart';

/// Fail-fast startup (matches [CompositionRoot.bootstrap]'s documented
/// intent): build the process-wide composition root — opening the Postgres
/// connection and validating Supabase auth config — BEFORE accepting any
/// request, so a misconfiguration surfaces immediately in the boot log, not
/// as a 500 on whichever request happens to arrive first.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  final root = await CompositionRoot.instance();

  // In-process schedulers are ON by default. NUKHBA_SCHEDULERS=off skips
  // all of them: a local server on a shared database must not race the
  // deployed one (see scheduler_switch.dart).
  if (schedulersEnabled(Platform.environment)) {
    // The prediction reminder runs on a timer inside this process (see
    // reminder_scheduler.dart for why not pg_cron).
    startReminderScheduler(root);
    // Pushes the followers of a team whose match starts soon (see
    // pre_match_scheduler.dart).
    startPreMatchScheduler(root);
    // Warns a player whose run breaks at the next kickoff (see
    // streak_saver_scheduler.dart).
    startStreakSaverScheduler(root);
    // Tells a player who predicted part of the day how many matches are
    // still open (see incomplete_day_scheduler.dart).
    startIncompleteDayScheduler(root);
    // The weekly league was retired on 2026-10-18 (script 113): its weekly
    // closure and its "overtaken" pushes no longer run. The head-to-head
    // league below replaced it.
    // Delivers the pushes deferred out of quiet hours (see
    // notification_queue_scheduler.dart).
    startNotificationQueueScheduler(root);
    // Keeps the next monthly contest in place without an admin (see
    // monthly_season_scheduler.dart).
    startMonthlySeasonScheduler(root);
    startMatchDaySettlementScheduler(root);
    // Finishes the scoring of results whose scoring failed after they
    // were recorded (see rescore_scheduler.dart).
    startRescoreScheduler(root);
    // Approves and locks the head-to-head rounds, judges each month and
    // draws the next (see h2h_league_scheduler.dart).
    startH2hLeagueScheduler(root);
    // Awards the badges players have earned (see
    // badge_evaluation_scheduler.dart).
    startBadgeEvaluationScheduler(root);
    // Automatic fixtures/results (off unless configured; see
    // provider_sync_scheduler.dart).
    startProviderSyncScheduler(root);
  } else {
    // ignore: avoid_print
    print('schedulers: disabled by $schedulersEnvKey=off');
  }

  final server = await serve(handler, ip, port);
  _stopOnSigterm(server, root);
  return server;
}

/// Stops cleanly when the platform stops the container (audit M-28).
///
/// A redeploy sends SIGTERM and kills the process a while later. The server
/// now stops taking connections, lets the requests and sweeps in progress
/// finish (20 seconds at most), closes the database pool and exits, instead
/// of being cut wherever it was.
void _stopOnSigterm(HttpServer server, CompositionRoot root) {
  var stopping = false;
  ProcessSignal.sigterm.watch().listen((_) async {
    if (stopping) {
      return;
    }
    stopping = true;
    // ignore: avoid_print
    print('SIGTERM: finishing requests and sweeps, then stopping');
    try {
      await Future.wait<void>(<Future<void>>[
        server.close(),
        drainSweeps(),
      ]).timeout(const Duration(seconds: 20), onTimeout: () => const <void>[]);
      await root.dispose();
    } on Object {
      // Stopping anyway: the platform kills the process soon after.
    }
    exit(0);
  });
}
