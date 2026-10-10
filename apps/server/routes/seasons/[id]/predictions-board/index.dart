import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/predictions_board_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /seasons/{id}/predictions-board?fixtures=<id>,<id>,...` -- the
/// players' predictions board of a day in one answer (2026-10-11): for each
/// fixture, everyone's predictions with their names, the scores and the
/// recorded result, and the reactions with the caller's own.
///
/// Replaces three requests per fixture (63 for a day of 21 matches, which
/// on 2026-10-10 held the server for over ten seconds). Each fixture passes
/// the same gate as `GET .../fixtures/{id}/predictions` -- a member of the
/// season, a linked, visible fixture that has kicked off by the server
/// clock -- and a refused fixture comes back as a column with its code, so
/// one refusal never hides the rest.
///
/// 1 to 40 fixture ids, comma separated; anything else is `400`
/// (`board.fixtures_invalid`). The `/seasons` subtree is behind
/// `bearerAuth`. `405` on any non-GET method.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final raw = context.request.uri.queryParameters['fixtures'] ?? '';
  final fixtureIds = [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getPredictionsBoard(
    principal: principal,
    seasonId: id,
    fixtureIds: fixtureIds,
  );

  return switch (result) {
    Ok<List<PredictionsBoardColumn>>(:final value) => Response.json(
      body: predictionsBoardToJson(id, value),
    ),
    Err<List<PredictionsBoardColumn>>(:final error) => errorResponse(error),
  };
}
