import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/teams` -- adds a club to the team catalog (command
/// `AdminAddTeam`, migration 0173, script 91), so a match is added with
/// both its clubs picked from the list.
///
/// Body: `{"name": string, "league_id": uuid | null}`. Answers the club
/// added as a `TeamDto` (`201`), with no crest and no short name. A club
/// whose name has the same spelling key is already on file: `409`
/// `football_data.team_exists`, its Arabic message naming that club. A
/// missing or wrong-typed field is `400`; any other method is `405`. Admin
/// only: the gate lives in the use-case.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final nameResult = requireString(body, 'name');
  if (nameResult is Err<String>) {
    return errorResponse(nameResult.error);
  }
  final leagueResult = optionalString(body, 'league_id');
  if (leagueResult is Err<String?>) {
    return errorResponse(leagueResult.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminAddTeam(
    principal: principal,
    name: (nameResult as Ok<String>).value,
    leagueId: (leagueResult as Ok<String?>).value,
  );

  return switch (result) {
    Ok<Team>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: teamToDto(value).toJson(),
    ),
    Err<Team>(:final error) => errorResponse(error),
  };
}
