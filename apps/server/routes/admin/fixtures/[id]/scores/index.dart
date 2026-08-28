import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_score_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/fixtures/{id}/scores` — the admin fixture-scores read: every
/// participant's already-computed score for a single fixture, regardless of
/// the admin's own season membership (docs/project-context.md, Axiom 4
/// Amendment; mirrors `GET /admin/rounds/{id}/scores`, admin-only, enforced
/// inside `AdminGetFixtureScores`).
///
/// Unlike the participant-facing
/// `GET /seasons/{id}/fixtures/{fixtureId}/scores` (season-membership
/// gated), this route carries NO such gate — added for admin investigation
/// of a user's complaint on any fixture. Also unlike
/// `GET /admin/rounds/{id}/scores` (blocked until the round is scored), this
/// carries no fixture-status gate either, mirroring `GetFixtureScores`'s
/// Option-3 live/partial philosophy: an empty array is a legitimate `200`,
/// not an error.
///
/// The whole `/admin` subtree is already behind `bearerAuth`
/// (`routes/admin/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this
/// handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminGetFixtureScores(
    principal: principal,
    fixtureId: id,
  );

  return switch (result) {
    Ok<List<ParticipantFixtureScore>>(:final value) => await _withDisplayNames(
      root,
      principal,
      id,
      value,
    ),
    Err<List<ParticipantFixtureScore>>(:final error) => errorResponse(error),
  };
}

Future<Response> _withDisplayNames(
  CompositionRoot root,
  AuthenticatedUser principal,
  String fixtureId,
  List<ParticipantFixtureScore> scores,
) async {
  final namesResult = await root.adminGetParticipantDisplayNames(
    principal: principal,
    participantIds: [for (final s in scores) s.participantId.value],
  );
  final names = namesResult is Ok<Map<String, String>>
      ? namesResult.value
      : const <String, String>{};
  return Response.json(
    body: fixtureScoresToJson(fixtureId, scores, displayNames: names),
  );
}
