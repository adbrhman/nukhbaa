import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_score_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /seasons/{id}/fixtures/{fixtureId}/scores` — read every
/// participant's already-computed score for a single fixture within a
/// season (API ADR §2: query intent `GetFixtureScores`;
/// docs/project-context.md, Axiom 4 Amendment — Step 1 of the 7.10.x
/// Round -> Season/Fixture migration).
///
/// Scoped under `/seasons` — not `/fixtures` — because the visibility gate
/// is season membership, not the fixture alone. Distinct from the existing
/// `POST /fixtures/{id}/score`, which triggers scoring rather than reading
/// it (plural `scores` in the path marks the difference).
///
/// Visibility gate: unlike `GET /rounds/{id}/scores` (blocked until the
/// round is fully scored), this follows `GetSeasonFixtureLeaderboard`'s
/// live/partial philosophy — only membership in the season is required. An
/// empty list before the fixture has been scored is a legitimate `200`, not
/// an error.
///
/// The whole `/seasons` subtree is already behind `bearerAuth`
/// (`routes/seasons/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this
/// handler.
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

  final result = await root.getFixtureScores(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<List<ParticipantFixtureScore>>(:final value) => Response.json(
      body: fixtureScoresToJson(fixtureId, value),
    ),
    Err<List<ParticipantFixtureScore>>(:final error) => errorResponse(error),
  };
}
