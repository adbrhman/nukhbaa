import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/competition_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// GET /leagues -- the Football Data league catalog (query intent
/// `ListLeagues`), so the admin fixture form can attach a `league_id` by
/// picking a name instead of leaving it null.
///
/// Read-only, no side effect. Returns a JSON array of [LeagueDto], the same
/// envelope convention as `GET /teams`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listLeagues(principal: principal);

  return switch (result) {
    Ok<List<League>>(:final value) => Response.json(
      body: [for (final l in value) leagueToDto(l).toJson()],
    ),
    Err<List<League>>(:final error) => errorResponse(error),
  };
}
