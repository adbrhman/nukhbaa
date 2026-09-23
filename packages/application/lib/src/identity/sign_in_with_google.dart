/// Use-case: sign in (or sign up) with a Google ID token.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:shared/shared.dart';

/// Exchanges a Google ID token, obtained on the device, for a platform
/// session through the [AuthGateway]. The identity provider creates the
/// account on first use and links it to an existing one with the same
/// verified email, so nobody signs up twice.
final class SignInWithGoogle {
  /// Creates the use-case with its required [AuthGateway] port.
  const SignInWithGoogle(this._gateway);

  final AuthGateway _gateway;

  /// Executes the sign-in. Never throws; returns a typed [Result]. A blank
  /// token is refused here, without a round trip to the identity provider.
  Future<Result<IssuedSession>> call({required String idToken}) async {
    final String token = idToken.trim();
    if (token.isEmpty) {
      return const Result.err(
        AppError.validation(
          'auth.google_token_required',
          'Google sign-in did not complete. Please try again.',
        ),
      );
    }
    return _gateway.signInWithIdToken(provider: 'google', idToken: token);
  }
}
