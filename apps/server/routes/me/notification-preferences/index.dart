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
/// notification switches (P3-1, pre_match from migration 0066).
///
/// `GET` answers the stored switches, or the defaults (all on) for a caller
/// who never changed anything. `PUT` takes any of
/// `{ "prediction_reminder": bool, "pre_match": bool }` -- at least one --
/// keeps the stored value of a switch the body leaves out, and answers what
/// was stored. An older client that only knows the reminder therefore never
/// resets the pre-match switch. The owner comes from the verified token,
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

    final reminder = _optionalBool(body, 'prediction_reminder');
    if (reminder is Err<bool?>) {
      return errorResponse(reminder.error);
    }
    final preMatch = _optionalBool(body, 'pre_match');
    if (preMatch is Err<bool?>) {
      return errorResponse(preMatch.error);
    }
    final streakSaver = _optionalBool(body, 'streak_saver');
    if (streakSaver is Err<bool?>) {
      return errorResponse(streakSaver.error);
    }
    final overtaken = _optionalBool(body, 'overtaken');
    if (overtaken is Err<bool?>) {
      return errorResponse(overtaken.error);
    }
    final bool? reminderValue = (reminder as Ok<bool?>).value;
    final bool? preMatchValue = (preMatch as Ok<bool?>).value;
    final bool? streakSaverValue = (streakSaver as Ok<bool?>).value;
    final bool? overtakenValue = (overtaken as Ok<bool?>).value;
    if (reminderValue == null &&
        preMatchValue == null &&
        streakSaverValue == null &&
        overtakenValue == null) {
      return errorResponse(
        const AppError.validation(
          'request.field_missing',
          'At least one notification switch is required',
        ),
      );
    }

    final root = await context.read<Future<CompositionRoot>>();
    final principal = context.read<AuthenticatedUser>();
    final current = await root.getMyNotificationPreferences(
      principal: principal,
    );
    if (current is Err<NotificationPreferences>) {
      return errorResponse(current.error);
    }
    final stored = (current as Ok<NotificationPreferences>).value;
    result = await root.updateMyNotificationPreferences(
      principal: principal,
      preferences: NotificationPreferences(
        predictionReminder: reminderValue ?? stored.predictionReminder,
        preMatch: preMatchValue ?? stored.preMatch,
        streakSaver: streakSaverValue ?? stored.streakSaver,
        overtaken: overtakenValue ?? stored.overtaken,
      ),
    );
  }

  return switch (result) {
    Ok<NotificationPreferences>(:final value) => Response.json(
      body: NotificationPreferencesDto(
        predictionReminder: value.predictionReminder,
        preMatch: value.preMatch,
        streakSaver: value.streakSaver,
        overtaken: value.overtaken,
      ).toJson(),
    ),
    Err<NotificationPreferences>(:final error) => errorResponse(error),
  };
}

/// Reads an optional boolean field: absent is `Ok(null)`, a boolean is
/// itself, anything else is refused -- a switch is never guessed from a
/// string or a number.
Result<bool?> _optionalBool(Map<String, Object?> body, String field) {
  if (!body.containsKey(field)) {
    return const Result.ok(null);
  }
  final value = body[field];
  if (value is bool) {
    return Result.ok(value);
  }
  return Result.err(
    AppError.validation(
      'request.field_missing',
      'Field "$field" must be a boolean',
    ),
  );
}
