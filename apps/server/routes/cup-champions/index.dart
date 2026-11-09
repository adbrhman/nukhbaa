import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/cup_champion_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /cup-champions` -- the champions of the Elite Cup (migrations 0190
/// and 0204), newest month first: the three paths of each month, with the
/// picture an admin added and the champion's own avatar when there are any.
/// Any signed-in player; any other method is `405`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final cup = root.cupChampions;
  if (cup == null) {
    return errorResponse(
      const AppError.transient(
        'cup.unavailable',
        'The cup champions are unavailable',
      ),
    );
  }
  final result = await cup.list(principal: principal);
  return switch (result) {
    Ok<List<CupChampion>>(:final value) => Response.json(
      body: cupChampionsToDto(value).toJson(),
    ),
    Err<List<CupChampion>>(:final error) => errorResponse(error),
  };
}
