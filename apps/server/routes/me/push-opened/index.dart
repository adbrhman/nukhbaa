import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /me/push-opened` -- the caller tapped a push carrying `link`
/// (plan P3-8), for the open rate of `notification.kpi_push_funnel`.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final link = requireString(
    (bodyResult as Ok<Map<String, Object?>>).value,
    'link',
  );
  if (link is Err<String>) {
    return errorResponse(link.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.recordPushOpen(
    principal: principal,
    link: (link as Ok<String>).value,
  );

  return switch (result) {
    Ok<void>() => Response.json(
      body: const PushOpenedAckDto(recorded: true).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
