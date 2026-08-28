// ignore_for_file: file_names
//
// The hyphen is required, not a style slip: dart_frog derives the route
// path from this file's name verbatim, and `GET /me/fixture-predictions`
// (matching PredictionApi.myFixturePredictions and its tests) is only
// produced by this exact file name.

import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_prediction_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /me/fixture-predictions — the caller's own aggregated
/// fixture-prediction history: every per-fixture prediction they have ever
/// submitted, across every fixture and every season (docs/project-context.md,
/// Axiom 4 Amendment; the per-fixture sibling of `GET /me/predictions`,
/// mirroring `routes/me/predictions.dart`).
///
/// **Visibility:** always the caller's own predictions, regardless of fixture
/// status — there is no season-membership check to perform at this route:
/// `ListMyFixturePredictions` already scopes the read to
/// `AuthenticatedUser.userId`, so nothing here can reveal another user's
/// prediction. This route only wires the verified principal and shapes the
/// result; it makes no authorization decision of its own.
///
/// The `/me` subtree is already behind `bearerAuth`
/// (`routes/me/_middleware.dart`), which provides the [AuthenticatedUser]; an
/// unauthenticated request never reaches this handler. Returns a JSON array of
/// [FixturePredictionDto], newest submission first (`200`); an empty array
/// means the caller has never submitted a fixture prediction, a legitimate
/// result, never an error. `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMyFixturePredictions(principal: principal);

  return switch (result) {
    Ok<List<FixturePredictionView>>(:final value) => Response.json(
      body: [for (final view in value) fixturePredictionViewToJson(view)],
    ),
    Err<List<FixturePredictionView>>(:final error) => errorResponse(error),
  };
}
