import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_score_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /fixtures/{id}/score` — score every prediction recorded for a single
/// fixture (API ADR §2: command intent `ScoreFixture`; docs/project-context.md,
/// Axiom 4 Amendment — "ScoreFixture replaces ScoreRound", the per-fixture
/// sibling of `POST /rounds/{id}/score`, so a fixture's predictions can be
/// graded the instant its actual result lands — never waiting on the rest of
/// any round). Admin-only, enforced inside the use-case (Axioms 2/5: only the
/// platform computes and writes points).
///
/// No request body: the actual scoreline was already ingested separately by
/// the admin `PUT /fixtures/{id}/result` command, and points are computed
/// server-side from the platform's current ruleset (see the reproducibility
/// gap noted on `ScoreFixture` — unlike `ScoreRound` there is no frozen
/// per-round snapshot to replay yet).
///
/// Idempotent: re-scoring an already-scored fixture recomputes the same
/// deterministic result and re-persists it in place, never duplicating rows.
/// Returns the computed [FixtureScoresDto] (`200`); a fixture with no
/// predictions surfaces as `409` `scoring.fixture_has_no_predictions` via the
/// shared error envelope.
///
/// The `/fixtures` subtree is already behind `bearerAuth`
/// (`routes/fixtures/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.scoreFixture(principal: principal, fixtureId: id);

  return switch (result) {
    Ok<List<ParticipantFixtureScore>>(:final value) => Response.json(
      body: fixtureScoresToJson(id, value),
    ),
    Err<List<ParticipantFixtureScore>>(:final error) => errorResponse(error),
  };
}
