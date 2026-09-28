import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/champion_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /champions` -- every crowned champion of the monthly contests,
/// newest crowning first (migration 0077). Each row carries the moment the
/// celebration ends (`celebrate_until`, 48 hours after the crowning), the
/// celebration picture and the champion's own avatar when there are any.
/// Any signed-in player; any other method is `405`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMonthChampions(principal: principal);

  return switch (result) {
    Ok<List<MonthChampion>>(:final value) => Response.json(
      body: monthChampionsToDto(value).toJson(),
    ),
    Err<List<MonthChampion>>(:final error) => errorResponse(error),
  };
}
