import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/leagues` -- adds a league to the league catalog (command
/// `AdminAddLeague`, migration 0183, script 139), so a match of a
/// competition the list lacks is filed under its own name.
///
/// Body: `{"name": string}`. Answers the league added as a `LeagueDto`
/// (`201`), continental, with no logo and no short name. A league whose
/// name has the same spelling key is already on file: `409`
/// `football_data.league_exists`, its Arabic message naming that league. A
/// missing or wrong-typed name is `400`; any other method is `405`. Admin
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

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminAddLeague(
    principal: principal,
    name: (nameResult as Ok<String>).value,
  );

  return switch (result) {
    Ok<League>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: leagueToDto(value).toJson(),
    ),
    Err<League>(:final error) => errorResponse(error),
  };
}
