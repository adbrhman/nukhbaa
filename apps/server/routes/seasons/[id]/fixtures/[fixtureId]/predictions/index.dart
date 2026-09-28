import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_prediction_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /seasons/{id}/fixtures/{fixtureId}/predictions` -- every member's
/// prediction for one fixture, each with the name it plays under, revealed
/// only once the fixture has kicked off (`ListFixturePredictions`).
///
/// Before kickoff the use-case refuses `409 prediction.fixture_not_started`,
/// so no prediction can be seen while any prediction can still be changed.
/// A started fixture nobody predicted is a legitimate empty array.
///
/// The `/seasons` subtree is behind `bearerAuth`
/// (`routes/seasons/_middleware.dart`). `405` on any non-GET method.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listFixturePredictions(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<FixturePredictionReveal>(:final value) => Response.json(
      body: [
        for (final view in value.predictions)
          fixturePredictionViewToJson(
            view,
            displayName:
                value.displayNames[view.prediction.participantId.value] ?? '',
          ),
      ],
    ),
    Err<FixturePredictionReveal>(:final error) => errorResponse(error),
  };
}
