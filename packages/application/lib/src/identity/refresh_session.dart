/// Use-case: renew a session from its refresh token.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:shared/shared.dart';

/// Renews a session through the platform's [AuthGateway], so a signed-in
/// user is not sent back to the sign-in screen just because an access token
/// aged out.
final class RefreshSession {
  /// Creates the use-case with its required [AuthGateway] port.
  const RefreshSession(this._gateway);

  final AuthGateway _gateway;

  /// Executes the renewal. Never throws; returns a typed [Result]. A blank
  /// token is refused here, without a round trip to the identity provider.
  Future<Result<IssuedSession>> call({required String refreshToken}) async {
    final String token = refreshToken.trim();
    if (token.isEmpty) {
      return const Result.err(
        AppError.validation(
          'auth.refresh_token_required',
          'Your session has ended. Please sign in again.',
        ),
      );
    }
    return _gateway.refreshSession(refreshToken: token);
  }
}
