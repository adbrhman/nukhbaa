import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/h2h/seats` -- seats a player late in an empty seat of a
/// head-to-head group (migration 0101). Body: `{"league_id": uuid,
/// "user_id": uuid, "slot": 0.., "day": "YYYY-MM-DD"?}`; the day picks the
/// month (today's by default). Answers `201 {"seated": true}`; the seat is
/// written to the admin log.
///
/// A malformed id is `400`, a slot that is not a whole number is `400`
/// (`h2h.slot_invalid`), a malformed day is `400` (`h2h.day_invalid`). A
/// month not drawn or judged, a group of another month, a seat outside the
/// group or taken, and a player seated already or unknown are `409`.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;
  final rawLeague = body['league_id'];
  final leagueId = H2hLeagueId.tryParse(rawLeague is String ? rawLeague : null);
  if (leagueId is Err<H2hLeagueId>) {
    return errorResponse(leagueId.error);
  }
  final rawUser = body['user_id'];
  final userId = UserId.tryParse(rawUser is String ? rawUser : null);
  if (userId is Err<UserId>) {
    return errorResponse(userId.error);
  }
  final slot = body['slot'];
  if (slot is! int) {
    return errorResponse(
      const AppError.validation(
        'h2h.slot_invalid',
        'Field "slot" must be a whole number',
      ),
    );
  }
  final rawDay = body['day'];
  final day = rawDay is String ? parseIsoDay(rawDay) : null;
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

  final result = await root.h2hAdminDesk.controls.addSeat(
    principal: principal,
    leagueId: (leagueId as Ok<H2hLeagueId>).value,
    userId: (userId as Ok<UserId>).value,
    slot: slot,
    day: day,
  );

  return switch (result) {
    Ok<void>() => Response.json(
      statusCode: HttpStatus.created,
      body: const {'seated': true},
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
