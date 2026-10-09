import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `GET /admin/h2h/rounds` -- a month's approved rounds and the days that
/// may be approved next (migration 0100). `?day=YYYY-MM-DD` picks the month
/// containing that day; today's month by default.
///
/// `POST /admin/h2h/rounds` -- approves a day as the next round of its
/// month. Body: `{"day": "YYYY-MM-DD"}`. Answers the new round (`201`).
/// A day already started, out of order, with too few matches or past the
/// nineteenth round is `409` with an `h2h.round_*` code.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`. A day
/// that is not a `YYYY-MM-DD` date is `400`.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => _list(context),
    HttpMethod.post => _approve(context),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _list(RequestContext context) async {
  final rawDay = context.request.uri.queryParameters['day'];
  final day = parseIsoDay(rawDay);
  if (rawDay != null && day == null) {
    return errorResponse(_dayInvalid);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listH2hRounds(principal: principal, day: day);

  return switch (result) {
    Ok<H2hRoundsOverview>(:final value) => Response.json(
      body: h2hRoundsOverviewToDto(value).toJson(),
    ),
    Err<H2hRoundsOverview>(:final error) => errorResponse(error),
  };
}

Future<Response> _approve(RequestContext context) async {
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;
  final raw = body['day'];
  final day = raw is String ? parseIsoDay(raw) : null;
  if (day == null) {
    return errorResponse(_dayInvalid);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.approveH2hRound(principal: principal, day: day);

  return switch (result) {
    Ok<H2hRound>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: h2hRoundToDto(value).toJson(),
    ),
    Err<H2hRound>(:final error) => errorResponse(error),
  };
}

const AppError _dayInvalid = AppError.validation(
  'h2h.day_invalid',
  'Field "day" must be a date written YYYY-MM-DD',
);
