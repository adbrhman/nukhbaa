import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_admin_dto_mapper.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/h2h/groups/{id}/rounds/{n}` -- every match of round [n] in
/// group [id] of a head-to-head month (migration 0100): who meets whom,
/// each side's stored points and who the round shows ahead. No prediction
/// of anybody is sent. `?day=YYYY-MM-DD` picks the month containing that
/// day; today's month by default.
///
/// A group id that is not a UUID is `400`; `n` outside 1..19 is `400`
/// (`h2h.round_invalid`). A group or round the month does not have is
/// `409` (`h2h.group_unknown`, `h2h.round_unknown`).
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context, String id, String n) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final leagueId = H2hLeagueId.tryParse(id);
  if (leagueId is Err<H2hLeagueId>) {
    return errorResponse(leagueId.error);
  }
  final round = int.tryParse(n);
  if (round == null ||
      '$round' != n ||
      round < 1 ||
      round > H2hLeaguePolicy.maxRounds) {
    return errorResponse(
      const AppError.validation(
        'h2h.round_invalid',
        'The round must be a number from 1 to 19',
      ),
    );
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

  final result = await root.h2hAdminDesk.groupRound(
    principal: principal,
    leagueId: (leagueId as Ok<H2hLeagueId>).value,
    round: round,
    day: day,
  );

  return switch (result) {
    Ok<H2hAdminGroupRound>(:final value) => Response.json(
      body: h2hAdminGroupRoundToDto(value).toJson(),
    ),
    Err<H2hAdminGroupRound>(:final error) => errorResponse(error),
  };
}
