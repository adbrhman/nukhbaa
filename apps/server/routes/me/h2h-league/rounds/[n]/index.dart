import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /me/h2h-league/rounds/{n}` -- round [n] of the caller's
/// head-to-head month in detail (migration 0100): every fixture with the
/// caller's pick, the opponent's pick, both sides' counts and the points.
///
/// **The opponent's pick of a fixture is sent only once that fixture has
/// kicked off** by the server clock (`FixtureLock`, the rule that closes
/// predictions); until then it is null and `theirs_hidden` is true. The
/// database read filters it the same way, so it never reaches this handler
/// early. Nothing is computed on the client (Axioms 2/5).
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

  final result = await root.getMyH2hRound(principal: principal, round: round);

  return switch (result) {
    Ok<MyH2hRoundDetail>(:final value) => Response.json(
      body: myH2hRoundToDto(value).toJson(),
    ),
    Err<MyH2hRoundDetail>(:final error) => errorResponse(error),
  };
}
