import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `PUT /admin/publisher/badges` -- sets a club's disc on the publisher's
/// pictures. Body: `{"team_id": uuid, "fill": "#RRGGBB", "label": "هلال"}`
/// (`label` optional: the club's name by default). Answers the badge.
/// Admin only.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final dto = PublisherBadgeDto.fromJson(
    (bodyResult as Ok<Map<String, Object?>>).value,
  );
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final adminRead = adminPublisherOf(root);
  if (adminRead is Err<AdminPublisher>) {
    return errorResponse(adminRead.error);
  }
  final result = await (adminRead as Ok<AdminPublisher>).value.setBadge(
    principal: principal,
    teamId: dto.teamId,
    fill: dto.fill,
    label: dto.label,
  );
  return switch (result) {
    Ok<StoredBadge>(:final value) => Response.json(
      body: PublisherBadgeDto(
        teamId: value.teamId,
        teamName: value.teamName,
        fill: value.fill,
        label: value.label,
      ).toJson(),
    ),
    Err<StoredBadge>(:final error) => errorResponse(error),
  };
}
