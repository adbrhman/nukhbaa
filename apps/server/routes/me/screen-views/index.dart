import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/rate_limit.dart';
import 'package:shared/shared.dart';

/// `POST /me/screen-views` -- how many times the caller opened each screen
/// since the app's last report (migration 0093), for the weekly usage of
/// every feature (`gamification.kpi_screen_usage_weekly`).
///
/// Body: `{"opens": {"<screen>": <count>, ...}}`. Inherits `bearerAuth`
/// from `routes/me/_middleware.dart`, so an unauthenticated request never
/// arrives here. The use-case drops a screen name it does not know and
/// refuses a count that cannot be true.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final Object? raw = (bodyResult as Ok<Map<String, Object?>>).value['opens'];
  if (raw is! Map<String, Object?> ||
      raw.values.any((Object? count) => count is! int)) {
    return errorResponse(
      const AppError.validation(
        'request.field_invalid',
        'Field "opens" must map screen names to integers',
      ),
    );
  }
  final Map<String, int> opens = <String, int>{
    for (final MapEntry<String, Object?> e in raw.entries)
      e.key: e.value as int,
  };

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final limited = limitPlayerAppend(PlayerAppend.screenViews, principal);
  if (limited != null) {
    return limited;
  }

  final result = await root.recordScreenViews(
    principal: principal,
    opens: opens,
  );

  return switch (result) {
    Ok<int>(:final value) => Response.json(
      body: ScreenViewsAckDto(recorded: value).toJson(),
    ),
    Err<int>(:final error) => errorResponse(error),
  };
}
