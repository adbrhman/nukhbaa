import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_groups_added_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/h2h/extra-groups` -- adds groups to the head-to-head month
/// open now (decided 2026-10-11). Body: `{"groups": 1..10}`. The players
/// with no seat this month who predicted on the settings' active days of
/// it, the most days first, are seated twenty to a group into the next
/// divisions of the ladder. Answers `201` with the groups, the seats and
/// how many qualified players are still waiting; the addition is written
/// to the admin log.
///
/// A count that is not a whole number is `400` (`h2h.groups_invalid`), one
/// outside 1..10 is `400` (`h2h.groups_out_of_range`). A month not drawn or
/// already judged, fewer than two players waiting, or a place taken
/// meanwhile is `409`.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final groups = (bodyResult as Ok<Map<String, Object?>>).value['groups'];
  if (groups is! int) {
    return errorResponse(
      const AppError.validation(
        'h2h.groups_invalid',
        'Field "groups" must be a whole number',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.addH2hGroups(principal: principal, groups: groups);

  return switch (result) {
    Ok<H2hGroupsAdded>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: h2hGroupsAddedToJson(value),
    ),
    Err<H2hGroupsAdded>(:final error) => errorResponse(error),
  };
}
