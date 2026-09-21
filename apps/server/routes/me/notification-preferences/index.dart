import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `GET` / `PUT /me/notification-preferences` -- the caller's own
/// notification switches (P3-1).
///
/// `GET` answers the stored switches, or the defaults (all on) for a caller
/// who never changed anything. `PUT` takes `{ "prediction_reminder": bool }`
/// and answers what was stored. The owner comes from the verified token,
/// never the body (Security ADR section 2).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final Result<NotificationPreferences> result;
  if (method == HttpMethod.get) {
    final root = await context.read<Future<CompositionRoot>>();
    final principal = context.read<AuthenticatedUser>();
    result = await root.getMyNotificationPreferences(principal: principal);
  } else {
    final bodyResult = await readJsonObject(context.request);
    if (bodyResult is Err<Map<String, Object?>>) {
      return errorResponse(bodyResult.error);
    }
    final body = (bodyResult as Ok<Map<String, Object?>>).value;

    final reminder = _requireBool(body, 'prediction_reminder');
    if (reminder is Err<bool>) {
      return errorResponse(reminder.error);
    }

    final root = await context.read<Future<CompositionRoot>>();
    final principal = context.read<AuthenticatedUser>();
    result = await root.updateMyNotificationPreferences(
      principal: principal,
      preferences: NotificationPreferences(
        predictionReminder: (reminder as Ok<bool>).value,
      ),
    );
  }

  return switch (result) {
    Ok<NotificationPreferences>(:final value) => Response.json(
      body: NotificationPreferencesDto(
        predictionReminder: value.predictionReminder,
      ).toJson(),
    ),
    Err<NotificationPreferences>(:final error) => errorResponse(error),
  };
}

/// Extracts a required boolean field. A switch has no safe default on write:
/// a body that forgot it must be refused, not read as "off" or "on".
Result<bool> _requireBool(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value is bool) {
    return Result.ok(value);
  }
  return Result.err(
    AppError.validation(
      'request.field_missing',
      'Field "$field" is required and must be a boolean',
    ),
  );
}
