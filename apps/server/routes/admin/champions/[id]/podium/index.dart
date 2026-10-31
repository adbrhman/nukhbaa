import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/champion_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /admin/champions/{seasonId}/podium` -- fixes the podium of a
/// crowned month (migration 0191): the first two players of its final board
/// after the champion(s) become the second and third places. No body.
/// Asked again, it answers the podium already set. Admin only.
///
/// Answers `{"podium": [...]}`, by place. Refusals are `409` with their
/// codes (`champion.not_crowned`, `champion.month_not_found`,
/// `champion.podium_refused`); a non-admin `401`. The pictures go through
/// `POST /admin/champions/{seasonId}/photos/{userId}`, which covers the
/// podium.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminSetMonthPodium(
    principal: principal,
    seasonId: id,
  );

  return switch (result) {
    Ok<List<MonthPodiumPlace>>(:final value) => Response.json(
      body: <String, Object?>{
        'podium': [
          for (final MonthPodiumPlace place in value)
            monthPodiumToDto(place).toJson(),
        ],
      },
    ),
    Err<List<MonthPodiumPlace>>(:final error) => errorResponse(error),
  };
}
