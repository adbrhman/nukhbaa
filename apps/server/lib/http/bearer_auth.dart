import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// Middleware that enforces Supabase bearer authentication on the routes it
/// guards, and provides the established [AuthenticatedUser] principal to
/// downstream handlers (Security ADR, Section 2; Application ADR, Section 12).
///
/// TWO stages, both mandatory:
/// 1. Cryptographic verification of the bearer token via
///    [AuthenticateRequest] (`root.authenticateRequest`) — proves the subject
///    only.
/// 2. Platform reconciliation via [GetCurrentUser] (`root.getCurrentUser`) —
///    the token says who the caller is; the platform's own `identity.users`
///    row says what authority they hold and whether they may act at all. The
///    principal handed to downstream handlers is rebuilt from that row, never
///    from token claims alone.
///
/// A suspended account is refused here, on every guarded request
/// (fail-closed), rather than retaining access until token expiry. A stored
/// `admin`/`service` role becomes reachable because it is read from the
/// directory row, not re-derived from the token on every request.
Middleware bearerAuth() {
  return (handler) {
    return (context) async {
      final root = await context.read<Future<CompositionRoot>>();

      // dart_frog lowercases header names; `authorizationHeader` is the
      // canonical lowercase `'authorization'` key.
      final header = context.request.headers[HttpHeaders.authorizationHeader];

      final verifyResult = await root.authenticateRequest(header);
      if (verifyResult case Err<AuthenticatedUser>(:final error)) {
        return errorResponse(error);
      }
      final tokenPrincipal = (verifyResult as Ok<AuthenticatedUser>).value;

      // The platform's canonical record. A transient directory failure is a
      // 503, never a silent downgrade to token-derived authority.
      final directoryResult = await root.getCurrentUser(tokenPrincipal);
      if (directoryResult case Err<User>(:final error)) {
        return errorResponse(error);
      }
      final user = (directoryResult as Ok<User>).value;

      if (!user.canAct) {
        return errorResponse(
          const AppError.authorization(
            'auth.user_suspended',
            'This account is suspended',
          ),
        );
      }

      // Authority comes from the stored row, identity from the verified
      // token; email falls back to the token's if the row has none yet.
      final principal = AuthenticatedUser(
        userId: user.id,
        role: user.role,
        email: user.email ?? tokenPrincipal.email,
      );

      return handler(context.provide<AuthenticatedUser>(() => principal));
    };
  };
}
