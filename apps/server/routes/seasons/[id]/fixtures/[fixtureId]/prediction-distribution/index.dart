import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_prediction_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /seasons/{id}/fixtures/{fixtureId}/prediction-distribution` —
/// aggregate home/away win shares for the match card. Individual predictions
/// are never exposed.
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

  final result = await root.getFixturePredictionDistribution(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<FixturePredictionDistribution>(:final value) => Response.json(
      body: fixturePredictionDistributionToJson(value),
    ),
    Err<FixturePredictionDistribution>(:final error) => errorResponse(error),
  };
}
