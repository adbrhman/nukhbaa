import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/scoring_dto_mapper.dart';
import 'package:shared/shared.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminGetRoundScores(
    principal: principal,
    roundId: id,
  );

  return switch (result) {
    Ok<List<RoundScore>>(:final value) => Response.json(
      body: roundScoresToJson(id, value),
    ),
    Err<List<RoundScore>>(:final error) => errorResponse(error),
  };
}
