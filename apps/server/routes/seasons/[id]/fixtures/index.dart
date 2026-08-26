import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `/seasons/{id}/fixtures` collection endpoint (Axiom 4 Amendment).
///
/// * `GET` — list the fixtures linked to the season, in display order, each
///   enriched with its schedule identity (team names + kickoff) for the
///   per-fixture prediction browse read (query intent `BrowseSeasonFixtures`;
///   the season-scoped sibling of `GET /rounds/{id}/fixtures` — read-only, no
///   side effect). A season with no linked fixtures, or one that does not
///   exist, yields a legitimate empty JSON array (no existence oracle).
/// * `POST` — link a fixture to the season (command intent
///   `LinkFixtureToSeason`; Phase 7.4 — the per-fixture sibling of
///   `POST /rounds/{id}/fixtures`, Axiom 4 Amendment). Admin-only (use-case
///   layer). Same URL as the `GET` above (2026-08 decision: no
///   `competitionId` in the path; the use-case reads it off the resolved
///   season internally).
///
/// Shares this folder with
/// `/seasons/{id}/fixtures/{fixtureId}/prediction` (the per-fixture prediction
/// write path). Both branches are authenticated (bearerAuth middleware via
/// `seasons/_middleware.dart`). Any other method is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _list(context, id),
    HttpMethod.post => _create(context, id),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

/// GET /seasons/{id}/fixtures — the fixtures browse, enriched with each
/// fixture's schedule identity (team names + kickoff) for the per-fixture
/// prediction browse read (unchanged read path).
Future<Response> _list(RequestContext context, String id) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.browseSeasonFixtures(
    principal: principal,
    seasonId: id,
  );

  return switch (result) {
    Ok<List<SeasonFixtureCard>>(:final value) => Response.json(
      body: [for (final card in value) seasonFixtureCardToDto(card).toJson()],
    ),
    Err<List<SeasonFixtureCard>>(:final error) => errorResponse(error),
  };
}

/// POST /seasons/{id}/fixtures — link a fixture to the season (new command
/// path, Phase 7.4.5).
Future<Response> _create(RequestContext context, String id) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final fixtureId = requireString(body, 'fixture_id');
  if (fixtureId is Err<String>) return errorResponse(fixtureId.error);
  final displayOrder = requireInt(body, 'display_order');
  if (displayOrder is Err<int>) return errorResponse(displayOrder.error);

  final result = await root.linkFixtureToSeason(
    principal: principal,
    seasonId: id,
    fixtureId: (fixtureId as Ok<String>).value,
    displayOrder: (displayOrder as Ok<int>).value,
  );

  return switch (result) {
    Ok<SeasonFixture>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: SeasonFixtureDto(
        seasonId: value.seasonId.value,
        fixtureId: value.fixture.value,
        displayOrder: value.displayOrder,
      ).toJson(),
    ),
    Err<SeasonFixture>(:final error) => errorResponse(error),
  };
}
