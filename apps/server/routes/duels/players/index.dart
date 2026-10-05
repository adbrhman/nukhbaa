import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/duel_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /duels/players?q=NAME` -- players to challenge privately (0092).
///
/// Answers `200` with `DuelPlayersDto`: active players whose display name
/// contains `q`, exact matches first, never the caller. A query shorter
/// than two characters answers an empty list.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.searchDuelPlayers(
    principal: principal,
    query: context.request.uri.queryParameters['q'] ?? '',
  );

  return switch (result) {
    Ok<List<DuelPlayer>>(:final value) => Response.json(
      body: duelPlayersToDto(value).toJson(),
    ),
    Err<List<DuelPlayer>>(:final error) => errorResponse(error),
  };
}
