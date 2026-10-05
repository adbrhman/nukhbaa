import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/duel_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /me/duels` -- the caller's open challenges and duels (migration
/// 0090).
///
/// The opponent's prediction appears only from kickoff on; points and the
/// winner only once both official fixture scores are final. Answers `200`
/// with `MyDuelsDto`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.listMyDuels(principal: principal);

  return switch (result) {
    Ok<MyDuels>(:final value) => Response.json(
      body: myDuelsToDto(value).toJson(),
    ),
    Err<MyDuels>(:final error) => errorResponse(error),
  };
}
