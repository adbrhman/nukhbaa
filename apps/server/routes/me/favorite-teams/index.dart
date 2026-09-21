import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `GET` / `PUT /me/favorite-teams` -- the teams the caller follows
/// (plan P3-1, migration 0065).
///
/// `GET` answers the stored ids, an empty list for a caller who never chose.
/// `PUT` takes `{ "team_ids": [uuid, ...] }` -- the whole set, at most three
/// -- and answers what was stored. An empty list clears it. The owner comes
/// from the verified token, never the body (Security ADR section 2).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final Result<FavoriteTeams> result;
  if (method == HttpMethod.get) {
    final root = await context.read<Future<CompositionRoot>>();
    final principal = context.read<AuthenticatedUser>();
    result = await root.getMyFavoriteTeams(principal: principal);
  } else {
    final bodyResult = await readJsonObject(context.request);
    if (bodyResult is Err<Map<String, Object?>>) {
      return errorResponse(bodyResult.error);
    }
    final body = (bodyResult as Ok<Map<String, Object?>>).value;

    final teams = _requireTeamIds(body);
    if (teams is Err<List<TeamRef>>) {
      return errorResponse(teams.error);
    }

    final root = await context.read<Future<CompositionRoot>>();
    final principal = context.read<AuthenticatedUser>();
    result = await root.setMyFavoriteTeams(
      principal: principal,
      teams: (teams as Ok<List<TeamRef>>).value,
    );
  }

  return switch (result) {
    Ok<FavoriteTeams>(:final value) => Response.json(
      body: FavoriteTeamsDto(
        teamIds: [for (final team in value.teams) team.value],
      ).toJson(),
    ),
    Err<FavoriteTeams>(:final error) => errorResponse(error),
  };
}

/// Extracts the required `team_ids` list. A set has no safe default on
/// write: a body that forgot it must be refused, not read as "clear all".
Result<List<TeamRef>> _requireTeamIds(Map<String, Object?> body) {
  final value = body['team_ids'];
  if (value is! List<Object?>) {
    return const Result.err(
      AppError.validation(
        'request.field_missing',
        'Field "team_ids" is required and must be a list of team ids',
      ),
    );
  }
  final teams = <TeamRef>[];
  for (final raw in value) {
    final parsed = TeamRef.tryParse(raw is String ? raw : null);
    if (parsed is Err<TeamRef>) {
      return Result.err(parsed.error);
    }
    teams.add((parsed as Ok<TeamRef>).value);
  }
  return Result.ok(teams);
}
