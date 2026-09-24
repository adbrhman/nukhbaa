import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/frame-stats` -- frame smoothness across every device
/// (migration 0070): totals over the last `?days=` days (default 7, at most
/// 30), overall and for the newest builds. Admin only: the gate lives in
/// the use-case, as for every admin read; a non-admin is refused as
/// `401 auth.insufficient_role`. `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final rawDays = context.request.uri.queryParameters['days'];

  final result = await root.adminGetFrameStats(
    principal: principal,
    days: rawDays == null ? null : int.tryParse(rawDays),
  );

  return switch (result) {
    Ok<FrameStats>(:final value) => Response.json(
      body: AdminFrameStatsDto(
        windowDays: value.windowDays,
        overall: _totals(value.overall),
        builds: [for (final b in value.builds) _totals(b)],
        devices: [
          for (final d in value.devices)
            DeviceTotalsDto(
              deviceModel: d.deviceModel,
              reports: d.reports,
              users: d.users,
              frames: d.frames,
              slowFrames: d.slowFrames,
              frozenFrames: d.frozenFrames,
            ),
        ],
      ).toJson(),
    ),
    Err<FrameStats>(:final error) => errorResponse(error),
  };
}

FrameTotalsDto _totals(FrameTotals t) => FrameTotalsDto(
  build: t.build,
  platform: t.platform,
  reports: t.reports,
  users: t.users,
  frames: t.frames,
  slowFrames: t.slowFrames,
  frozenFrames: t.frozenFrames,
  worstFrameMs: t.worstFrameMs,
  lastReportedAt: t.lastReportedAt?.toUtc().toIso8601String(),
);
