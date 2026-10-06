import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /seasons/{id}/duel-wins` -- how many duels each player of the
/// season won (`ListSeasonDuelWins`), shown beside their name on the
/// month's leaderboard. Only a member of the season sees it: otherwise
/// `401 leaderboard.not_a_participant`, as for the leaderboard itself.
///
/// The `/seasons` subtree is behind `bearerAuth`. `405` on any non-GET
/// method.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listSeasonDuelWins(
    principal: principal,
    seasonId: id,
  );

  return switch (result) {
    Ok<Map<ParticipantId, int>>(:final value) => Response.json(
      body: SeasonDuelWinsDto(
        wins: {for (final e in value.entries) e.key.value: e.value},
      ).toJson(),
    ),
    Err<Map<ParticipantId, int>>(:final error) => errorResponse(error),
  };
}
