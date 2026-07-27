import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/prediction_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /me/predictions — the caller's own aggregated prediction history: every
/// prediction they have ever submitted, across every round and every season
/// (API ADR §2: a query, separated from the submit command; mirrors
/// `GET /rounds/{id}/predictions/all`, but scoped to the caller's own forecasts
/// across time rather than one round's whole pool).
///
/// **Visibility:** always the caller's own predictions, regardless of round
/// status — unlike the round-scoped list (`ListRoundPredictions`), there is no
/// "round must be locked" gate here (a caller may always see their own
/// submitted forecasts) and no season-membership check to perform at this
/// route: `ListMyPredictions` already scopes the read to
/// `AuthenticatedUser.userId`, so nothing here can reveal another user's
/// prediction. This route only wires the verified principal and shapes the
/// result; it makes no authorization decision of its own.
///
/// The `/me` subtree is already behind `bearerAuth`
/// (`routes/me/_middleware.dart`), which provides the [AuthenticatedUser]; an
/// unauthenticated request never reaches this handler. Returns a JSON array of
/// [PredictionDto], newest submission first (`200`); an empty array means the
/// caller has never submitted a prediction, a legitimate result, never an
/// error. `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMyPredictions(principal: principal);

  return switch (result) {
    Ok<List<PredictionView>>(:final value) => Response.json(
      body: [for (final view in value) predictionViewToJson(view)],
    ),
    Err<List<PredictionView>>(:final error) => errorResponse(error),
  };
}
