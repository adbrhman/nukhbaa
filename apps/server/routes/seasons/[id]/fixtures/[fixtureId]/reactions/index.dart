import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /seasons/{id}/fixtures/{fixtureId}/reactions` -- the reactions every
/// prediction for the fixture received, with the caller's own (migration
/// 0094). Seen by whoever may see the predictions: a member of the season,
/// once the fixture has kicked off (`ListPredictionReactions`); before that
/// it is the same `409 prediction.fixture_not_started`.
///
/// The `/seasons` subtree is behind `bearerAuth`. `405` on any non-GET
/// method.
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

  final result = await root.listPredictionReactions(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<List<PredictionReactionTally>>(:final value) => Response.json(
      body: PredictionReactionsDto(
        reactions: [
          for (final tally in value)
            PredictionReactionTallyDto(
              participantId: tally.targetParticipantId.value,
              counts: {
                for (final e in tally.counts.entries) e.key.wireValue: e.value,
              },
              mine: tally.mine?.wireValue,
            ),
        ],
      ).toJson(),
    ),
    Err<List<PredictionReactionTally>>(:final error) => errorResponse(error),
  };
}
