import 'dart:async';
import 'dart:math';

import 'package:shared/shared.dart';

/// The header every response carries its request id in.
const String requestIdHeader = 'X-Request-Id';

/// What the error log needs to know about the request in flight, carried
/// in a [Zone] so the layers that learn it -- `bearerAuth` the player,
/// `errorResponse` the failure -- need no new parameter.
///
/// `captureServerErrors` opens one per request; outside a request (a
/// scheduler, a test calling a route directly) [current] is null and
/// nothing is noted.
final class RequestScope {
  /// Creates the scope of one request.
  RequestScope(this.requestId);

  static const Symbol _zoneKey = #nukhbaaRequestScope;

  static final Random _random = Random.secure();

  /// A new random request id: 32 hex digits.
  static String newRequestId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// The scope of the request this code runs in, if any.
  static RequestScope? get current => Zone.current[_zoneKey] as RequestScope?;

  /// This request's id, returned in [requestIdHeader].
  final String requestId;

  /// The signed-in player, once `bearerAuth` verified the token.
  String? userId;

  /// The error a route answered with a 5xx for, if any.
  AppError? serverError;

  /// Where [serverError] was answered.
  StackTrace? serverErrorStack;

  /// Runs [body] inside this scope.
  R run<R>(R Function() body) =>
      runZoned(body, zoneValues: <Object?, Object?>{_zoneKey: this});
}
