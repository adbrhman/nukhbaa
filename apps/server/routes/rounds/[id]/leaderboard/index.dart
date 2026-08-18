import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/leaderboard_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /rounds/{id}/leaderboard — read a round's ranked standings (API ADR §2:
/// a query; a round leaderboard is a read-side projection over that round's
/// already-computed scores — Axiom 5, never a points write, so there is no
/// command here).
///
/// The visibility gate lives entirely inside `GetRoundLeaderboard`, and is
/// identical to `GET /rounds/{id}/scores`'s: a round is rankable only once it
/// is `scored` (a not-yet-scored round is rejected `409`
/// `scoring.round_not_scored`), and only a participant of the round's season
/// may see the competing pool (a non-participant is rejected `401`
/// `scoring.not_a_participant`). This route only wires the verified principal
/// and the round id and shapes the result; it makes no authorization decision
/// of its own.
///
/// The `/rounds` subtree is already behind `bearerAuth`
/// (`routes/rounds/_middleware.dart`), which provides the [AuthenticatedUser];
/// an unauthenticated request never reaches this handler. Returns the
/// [RoundLeaderboardDto] (`200`); an empty `entries` array means the round is
/// scored but nobody predicted, distinct from the `409` "too early" case.
/// `405` on any non-GET method.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getRoundLeaderboard(
    principal: principal,
    roundId: id,
  );

  return switch (result) {
    Ok<RoundLeaderboard>(:final value) => Response.json(
      body: roundLeaderboardToJson(value),
    ),
    Err<RoundLeaderboard>(:final error) => errorResponse(error),
  };
}
