import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/leaderboard_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /leaderboard/season -- the current sporting season's standings: every
/// monthly contest from September to August summed per user, most points
/// first. Read-only; `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getSportingSeasonLeaderboard(principal: principal);

  return switch (result) {
    Ok<SportingSeasonLeaderboard>(:final value) => Response.json(
      body: sportingSeasonLeaderboardToJson(value),
    ),
    Err<SportingSeasonLeaderboard>(:final error) => errorResponse(error),
  };
}
