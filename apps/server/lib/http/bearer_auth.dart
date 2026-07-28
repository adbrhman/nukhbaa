import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

Middleware bearerAuth() {
  return (handler) {
    return (context) async {
      final root = await context.read<Future<CompositionRoot>>();

      final header = context.request.headers[HttpHeaders.authorizationHeader];

      final verified = await root.authenticateRequest(header);
      if (verified is Err<AuthenticatedUser>) {
        return errorResponse(verified.error);
      }
      final tokenPrincipal = (verified as Ok<AuthenticatedUser>).value;

      final canonical = await root.getCurrentUser(tokenPrincipal);
      if (canonical is Err<User>) {
        return errorResponse(canonical.error);
      }
      final user = (canonical as Ok<User>).value;

      if (!user.canAct) {
        return errorResponse(
          const AppError.authorization(
            'auth.user_suspended',
            'This account is suspended.',
          ),
        );
      }

      final effective = AuthenticatedUser(
        userId: user.id,
        role: user.role,
        email: user.email ?? tokenPrincipal.email,
      );

      return handler(
        context
            .provide<AuthenticatedUser>(() => effective)
            .provide<User>(() => user),
      );
    };
  };
}
