import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/reminder_scheduler.dart';

/// Fail-fast startup (matches [CompositionRoot.bootstrap]'s documented
/// intent): build the process-wide composition root — opening the Postgres
/// connection and validating Supabase auth config — BEFORE accepting any
/// request, so a misconfiguration surfaces immediately in the boot log, not
/// as a 500 on whichever request happens to arrive first.
Future<HttpServer> run(Handler handler, InternetAddress ip, int port) async {
  final root = await CompositionRoot.instance();

  // The prediction reminder runs on a timer inside this process (see
  // reminder_scheduler.dart for why not pg_cron).
  startReminderScheduler(root);

  return serve(handler, ip, port);
}
