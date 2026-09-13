import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// PUT /me/display-name -- retired surface. The platform display name is
/// chosen once, at registration (`POST /auth/register` requires it), and is
/// immutable from then on, so a rename is refused here instead of reaching
/// `UpdateDisplayName`. Kept as a stated 409 rather than a deleted route so
/// an older client is told WHY, not just that the path is gone. Still
/// inherits `bearerAuth` from `routes/me/_middleware.dart`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  return errorResponse(
    const AppError.invariant(
      'identity.display_name_immutable',
      'لا يمكن تغيير الاسم بعد التسجيل',
    ),
  );
}
