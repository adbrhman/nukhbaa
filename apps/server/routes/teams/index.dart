import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// GET /teams — the Football Data team catalog (API ADR §2: query intent
/// `ListTeams`), so a client can resolve a fixture's `home_team_id`/
/// `away_team_id` into a display name + crest without hardcoding either
/// client-side (previously unwired schema — `football_data.teams`, migration
/// `0013_football_data.sql`). Read-only, no side effect. Returns a JSON array
/// of [TeamDto], same envelope convention as `GET /competitions`.
///
/// The `/teams` subtree is already behind `bearerAuth`
/// (`routes/teams/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listTeams(principal: principal);

  return switch (result) {
    Ok<List<Team>>(:final value) => Response.json(
      body: [for (final t in value) teamToDto(t).toJson()],
    ),
    Err<List<Team>>(:final error) => errorResponse(error),
  };
}
