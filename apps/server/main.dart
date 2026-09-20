import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/match_day_settlement_scheduler.dart';
import 'package:server/scheduler/monthly_season_scheduler.dart';
import 'package:server/scheduler/provider_sync_scheduler.dart';
import 'package:server/scheduler/reminder_scheduler.dart';
import 'package:server/scheduler/scheduler_switch.dart';
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
    // Keeps the next monthly contest in place without an admin (see
    // monthly_season_scheduler.dart).
    startMonthlySeasonScheduler(root);
    startMatchDaySettlementScheduler(root);
    // Judges each weekly-league week once it has ended (see
    // weekly_league_closure_scheduler.dart).
    startWeeklyLeagueClosureScheduler(root);
    // Automatic fixtures/results (off unless configured; see
    // provider_sync_scheduler.dart).
    startProviderSyncScheduler(root);
  } else {
    // ignore: avoid_print
    print('schedulers: disabled by $schedulersEnvKey=off');
  }

  return serve(handler, ip, port);
}
