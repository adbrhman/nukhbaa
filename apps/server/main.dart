import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/badge_evaluation_scheduler.dart';
import 'package:server/scheduler/match_day_settlement_scheduler.dart';
import 'package:server/scheduler/monthly_season_scheduler.dart';
import 'package:server/scheduler/notification_queue_scheduler.dart';
import 'package:server/scheduler/overtaken_scheduler.dart';
import 'package:server/scheduler/pre_match_scheduler.dart';
import 'package:server/scheduler/provider_sync_scheduler.dart';
import 'package:server/scheduler/reminder_scheduler.dart';
import 'package:server/scheduler/scheduler_switch.dart';
import 'package:server/scheduler/streak_saver_scheduler.dart';
import 'package:server/scheduler/weekly_league_closure_scheduler.dart';

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
    // Tells a weekly-league member who was just overtaken (see
    // overtaken_scheduler.dart).
    startOvertakenScheduler(root);
    // Delivers the pushes deferred out of quiet hours (see
    // notification_queue_scheduler.dart).
    startNotificationQueueScheduler(root);
    // Keeps the next monthly contest in place without an admin (see
    // monthly_season_scheduler.dart).
    startMonthlySeasonScheduler(root);
    startMatchDaySettlementScheduler(root);
    // Judges each weekly-league week once it has ended (see
    // weekly_league_closure_scheduler.dart).
    startWeeklyLeagueClosureScheduler(root);
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

  return serve(handler, ip, port);
}
