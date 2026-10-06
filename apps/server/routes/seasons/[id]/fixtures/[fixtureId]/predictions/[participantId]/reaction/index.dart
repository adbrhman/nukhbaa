import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// The caller's reaction to one player's prediction (migration 0094):
///
/// * `PUT .../predictions/{participantId}/reaction` with `{"emoji": kind}`
///   reacts, or changes an earlier reaction (`ReactToPrediction`); answers
///   `{"reacted": true, "first": bool}`, `first` being true only for the
///   caller's first reaction to this prediction.
/// * `DELETE` takes it back (`RemovePredictionReaction`); answers
///   `{"removed": bool}`, false when there was none.
///
/// Both stand behind the predictions' own gate: a member of the season,
/// once the fixture has kicked off. Reacting to one's own prediction is
/// `409 social.prediction_reaction_self`. The `/seasons` subtree is behind
/// `bearerAuth`. `405` on any other method.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
  String participantId,
) async {
  final method = context.request.method;
  if (method != HttpMethod.put && method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  if (method == HttpMethod.delete) {
    final removed = await root.removePredictionReaction(
      principal: principal,
      seasonId: id,
      fixtureId: fixtureId,
      targetParticipantId: participantId,
    );
    return switch (removed) {
      Ok<bool>(:final value) => Response.json(body: {'removed': value}),
      Err<bool>(:final error) => errorResponse(error),
    };
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final emoji = requireString(
    (bodyResult as Ok<Map<String, Object?>>).value,
    'emoji',
  );
  if (emoji is Err<String>) {
    return errorResponse(emoji.error);
  }

  final result = await root.reactToPrediction(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
    targetParticipantId: participantId,
    emoji: (emoji as Ok<String>).value,
  );
  return switch (result) {
    Ok<PredictionReactionWrite>(:final value) => Response.json(
      body: {'reacted': true, 'first': value.inserted},
    ),
    Err<PredictionReactionWrite>(:final error) => errorResponse(error),
  };
}
