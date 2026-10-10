import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /me/h2h-league/rounds/{n}/matches` -- every match of round [n] in
/// the caller's own head-to-head group (migration 0100): who meets whom,
/// each side's stored points, and who the round shows ahead.
///
/// No prediction of anybody is sent. While the round is live, who is ahead
/// is by points alone, so the answer never tells whether a member has
/// predicted; once it is settled it is the policy's result. Only the
/// caller's group is read. Nothing is computed on the client (Axioms 2/5).
///
/// `n` is the round number, 1 to 19; anything else is `400`
/// (`h2h.round_invalid`). A caller with no seat this month is `409`
/// (`h2h.not_seated`), and so is a round the month does not have
/// (`h2h.round_unknown`).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context, String n) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
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

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getMyH2hGroupRound(
    principal: principal,
    round: round,
  );

  return switch (result) {
    Ok<MyH2hGroupRound>(:final value) => Response.json(
      body: h2hGroupRoundToDto(value).toJson(),
    ),
    Err<MyH2hGroupRound>(:final error) => errorResponse(error),
  };
}
