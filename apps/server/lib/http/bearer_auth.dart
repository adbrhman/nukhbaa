import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// Middleware that enforces Supabase bearer authentication on the routes it
/// guards, and provides the established [AuthenticatedUser] principal to
/// downstream handlers (Security ADR, Section 2; Application ADR, Section 12).
///
/// Verification AND platform reconciliation both happen inside
/// [AuthenticateRequest] (`root.authenticateRequest`): the token proves who
/// the caller is; the platform's own `identity.users` row — read there via
/// `UserDirectory.findUser` — says what authority they hold and whether they
/// may act at all. The principal handed to downstream handlers is the
/// reconciled result, never token claims alone.
///
/// A suspended account is refused inside [AuthenticateRequest] itself, on
/// every guarded request (fail-closed), rather than retaining access until
/// token expiry. A stored `admin`/`service` role becomes reachable because it
/// is read from the directory row, not re-derived from the token.
///
/// This middleware does NOT perform a second reconciliation pass. An earlier
/// version additionally called `GetCurrentUser` (which owns `ensureUser`, an
/// upsert) here, putting a write on the hottest path in the system and
/// producing a second, inconsistent suspension error code
/// (`auth.user_suspended` vs. `auth.account_suspended`). `ensureUser` /
/// `GetCurrentUser` are owned exclusively by the `GET /me` boundary.
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
      final principal = (verifyResult as Ok<AuthenticatedUser>).value;

      return handler(context.provide<AuthenticatedUser>(() => principal));
    };
  };
}
