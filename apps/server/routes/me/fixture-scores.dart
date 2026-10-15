// ignore_for_file: file_names
//
// The hyphen is required, not a style slip: dart_frog derives the route
// path from this file's name verbatim, and `GET /me/fixture-scores`
// (matching CompetitionApi.myFixtureScores and its tests) is only produced
// by this exact file name.

import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/my_fixture_score_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /me/fixture-scores -- the caller's own grade, points and final score
/// for every prediction that has a score or a recorded result, in one read
/// (script 75, migration 0171).
///
/// Before it the app asked `GET /seasons/{id}/fixtures/{fixtureId}/scores`
/// once per finished match card and once per row of "my predictions", and
/// again every 2 minutes while a score was pending; that route stays for apps
/// installed before this one.
///
/// **Visibility:** always the caller's own rows -- `ListMyFixtureScores`
/// scopes the read to `AuthenticatedUser.userId`; this route makes no
/// authorization decision of its own. The `/me` subtree is already behind
/// `bearerAuth` (`routes/me/_middleware.dart`).
///
/// Returns a JSON array of [MyFixtureScoreDto] (`200`); an empty array is a
/// caller with nothing scored or recorded yet, never an error. `405` on any
/// non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMyFixtureScores(principal: principal);

  return switch (result) {
    Ok<List<MyFixtureScore>>(:final value) => Response.json(
      body: [for (final score in value) myFixtureScoreToDto(score).toJson()],
    ),
    Err<List<MyFixtureScore>>(:final error) => errorResponse(error),
  };
}
