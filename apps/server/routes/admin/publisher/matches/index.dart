import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `PUT /admin/publisher/matches` -- picks a match for the publisher, or
/// stops covering it. Body: `{"fixture_id": uuid, "covered": true|false}`.
/// Answers `{"fixture_id": ..., "covered": ...}`. Stopping keeps the
/// match's goals and posts. Admin only.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;
  final Object? fixtureId = body['fixture_id'];
  final Object? covered = body['covered'];
  if (fixtureId is! String || covered is! bool) {
    return errorResponse(
      const AppError.validation(
        'publisher.coverage_invalid',
        'Fields "fixture_id" (string) and "covered" (bool) are required',
      ),
    );
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final adminRead = adminPublisherOf(root);
  if (adminRead is Err<AdminPublisher>) {
    return errorResponse(adminRead.error);
  }
  final result = await (adminRead as Ok<AdminPublisher>).value.setCovered(
    principal: principal,
    fixtureId: fixtureId,
    covered: covered,
  );
  return switch (result) {
    Ok<void>() => Response.json(
      body: <String, Object?>{'fixture_id': fixtureId, 'covered': covered},
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
