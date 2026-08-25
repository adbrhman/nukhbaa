import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `/seasons/{id}/fixtures` collection endpoint (Axiom 4 Amendment).
///
/// * `GET` — list the fixtures linked to the season, in display order, each
///   enriched with its schedule identity (team names + kickoff) for the
///   per-fixture prediction browse read (query intent `BrowseSeasonFixtures`;
///   the season-scoped sibling of `GET /rounds/{id}/fixtures` — read-only, no
///   side effect). A season with no linked fixtures, or one that does not
///   exist, yields a legitimate empty JSON array (no existence oracle).
///
/// Shares this folder with
/// `/seasons/{id}/fixtures/{fixtureId}/prediction` (the write path). Any
/// method other than `GET` is `405`. Authenticated (bearerAuth middleware via
/// `seasons/_middleware.dart`).
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.browseSeasonFixtures(
    principal: principal,
    seasonId: id,
  );

  return switch (result) {
    Ok<List<SeasonFixtureCard>>(:final value) => Response.json(
      body: [
        for (final card in value) seasonFixtureCardToDto(card).toJson(),
      ],
    ),
    Err<List<SeasonFixtureCard>>(:final error) => errorResponse(error),
  };
}
