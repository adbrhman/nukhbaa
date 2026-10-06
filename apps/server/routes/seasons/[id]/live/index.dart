import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /seasons/{id}/live` -- while the season's matches are in play, what
/// the caller's predictions would earn if they ended now, their place on
/// the month board now and then, and who leads each of their duels on them
/// (`GetLiveStanding`). Graded on the server; nothing is stored. Only a
/// member of the season reads it: otherwise `401
/// leaderboard.not_a_participant`, as for the leaderboard itself.
///
/// The `/seasons` subtree is behind `bearerAuth`. `405` on any non-GET
/// method.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getLiveStanding(principal: principal, seasonId: id);

  return switch (result) {
    Ok<LiveStanding>(:final value) => Response.json(
      body: LiveStandingDto(
        fixtures: [
          for (final LiveFixtureStanding f in value.fixtures)
            LiveFixtureStandingDto(
              fixtureId: f.fixture.value,
              homeGoals: f.homeGoals,
              awayGoals: f.awayGoals,
              minute: f.minute,
              finished: f.finished,
              myPoints: f.myPoints,
            ),
        ],
        duels: [
          for (final LiveDuelStanding d in value.duels)
            LiveDuelStandingDto(
              fixtureId: d.fixture.value,
              opponentName: d.opponentName,
              myPoints: d.myPoints,
              opponentPoints: d.opponentPoints,
            ),
        ],
        rankNow: value.rankNow,
        rankIfEnded: value.rankIfEnded,
        pointsNow: value.pointsNow,
        pointsIfEnded: value.pointsIfEnded,
        players: value.players,
      ).toJson(),
    ),
    Err<LiveStanding>(:final error) => errorResponse(error),
  };
}
