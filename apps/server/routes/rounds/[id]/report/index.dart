import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/scoring_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /rounds/{id}/report — every participant's correct/incorrect
/// fixture-grade counts and total points for a **scored** round (Task 5),
/// aggregated server-side over the same data `GET /rounds/{id}/scores`
/// reads. Shares that route's exact visibility gate via `GetRoundReport`: a
/// not-yet-scored round is `409 scoring.round_not_scored`; a non-participant
/// is `401 scoring.not_a_participant`.
///
/// The `/rounds` subtree is already behind `bearerAuth`
/// (`routes/rounds/_middleware.dart`).
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.getRoundReport(principal: principal, roundId: id);

  return switch (result) {
    Ok<List<RoundReportEntry>>(:final value) => Response.json(
      body: roundReportToJson(id, value),
    ),
    Err<List<RoundReportEntry>>(:final error) => errorResponse(error),
  };
}
