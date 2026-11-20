import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

AppModeDto _wire(AppModeState state, UserId reader) {
  final UserId? by = state.changedBy;
  return AppModeDto(
    mode: state.mode.wire,
    reason: state.reason,
    changedBy: by == null
        ? (state.reason == null ? null : OwnerSwitchDto.bySqlEditor)
        : (by == reader ? OwnerSwitchDto.byYou : OwnerSwitchDto.byOtherOwner),
    changedAt: state.changedAt,
  );
}

// NK292_07
/// `/owner/mode` -- the app's mode in the owners' hands (`OwnerAppMode`,
/// script 292, migration 0222).
///
/// * `GET` -- the mode and its last change.
/// * `PUT` `{"mode": "normal" | "read_only" | "closed", "reason": "..."}`
///   -- sets it, always for a reason; this server sees it at once, the
///   others within ten seconds. Answers it as it now stands.
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287). An
/// unknown mode is `400 owner.mode_unknown`; a blank or long reason
/// `400 owner.reason_required`. `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  final HttpMethod method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final OwnerAppMode? modes = root.ownerAppMode;
  if (modes == null) {
    return errorResponse(
      const AppError.transient(
        'owner.mode_unavailable',
        'The app mode is unavailable',
      ),
    );
  }
  final principal = context.read<AuthenticatedUser>();
  final Result<AppModeState> result;
  if (method == HttpMethod.put) {
    final bodyResult = await readJsonObject(context.request);
    if (bodyResult is Err<Map<String, Object?>>) {
      return errorResponse(bodyResult.error);
    }
    final Map<String, Object?> body =
        (bodyResult as Ok<Map<String, Object?>>).value;
    final Object? mode = body['mode'];
    final Object? reason = body['reason'];
    result = await modes.set(
      principal: principal,
      wire: mode is String ? mode : '',
      reason: reason is String ? reason : null,
    );
    if (result is Ok<AppModeState>) root.appModeCache?.forget();
  } else {
    result = await modes.state(principal: principal);
  }
  return switch (result) {
    Ok<AppModeState>(:final value) => Response.json(
      body: _wire(value, principal.userId).toJson(),
    ),
    Err<AppModeState>(:final error) => errorResponse(error),
  };
}
