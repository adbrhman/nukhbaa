import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/leaderboard_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /groups/{id}/seasons/{seasonId}/month-board` -- the friends'
/// league: the month's board narrowed to the group's members and ranked
/// among them (`GetGroupMonthBoard`), in the month board's own shape. Only
/// a member of the group reads it: otherwise `401 group.not_a_member`.
///
/// The `/groups` subtree is behind `bearerAuth`. `405` on any non-GET
/// method.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String seasonId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getGroupMonthBoard(
    principal: principal,
    groupId: id,
    seasonId: seasonId,
  );

  return switch (result) {
    Ok<FixtureLeaderboard>(:final value) => Response.json(
      body: fixtureLeaderboardToJson(value),
    ),
    Err<FixtureLeaderboard>(:final error) => errorResponse(error),
  };
}
