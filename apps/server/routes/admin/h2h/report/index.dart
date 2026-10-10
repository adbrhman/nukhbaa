import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_admin_dto_mapper.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/h2h/report` -- how a head-to-head month went (migration
/// 0101): its draw, its seats (the draw's and any added late), its groups
/// per division, and its closing with the members per outcome.
/// `?day=YYYY-MM-DD` picks the month containing that day; today's month by
/// default.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`. A day
/// that is not a `YYYY-MM-DD` date is `400` (`h2h.day_invalid`).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final rawDay = context.request.uri.queryParameters['day'];
  final day = parseIsoDay(rawDay);
  if (rawDay != null && day == null) {
    return errorResponse(
      const AppError.validation(
        'h2h.day_invalid',
        'Field "day" must be a date written YYYY-MM-DD',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.h2hAdminDesk.controls.report(
    principal: principal,
    day: day,
  );

  return switch (result) {
    Ok<H2hMonthReport>(:final value) => Response.json(
      body: h2hMonthReportToDto(value).toJson(),
    ),
    Err<H2hMonthReport>(:final error) => errorResponse(error),
  };
}
