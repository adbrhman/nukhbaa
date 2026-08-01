/// The application-owned port for email/password authentication. Concrete
/// implementations live in infrastructure (adapting the Supabase Auth REST
/// API); the application layer never depends on how a session is issued,
/// only on this contract.
library;

import 'package:shared/shared.dart';

/// A session issued by the identity provider on successful login/register.
///
/// [accessToken] is null exactly when [emailConfirmationRequired] is true:
/// the project requires the user to confirm their email before a session is
/// issued.
final class IssuedSession {
  /// Creates an issued session.
  const IssuedSession({
    required this.accessToken,
    required this.refreshToken,
    required this.emailConfirmationRequired,
  });

  /// The access token (a JWT), or null if email confirmation is pending.
  final String? accessToken;

  /// The refresh token, when present.
  final String? refreshToken;

  /// Whether the account was created but a session was withheld pending
  /// email confirmation.
  final bool emailConfirmationRequired;
}

/// Port: exchanges email/password credentials for an [IssuedSession].
abstract class AuthGateway {
  /// Signs in with an existing email/password account.
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  });

  /// Registers a new email/password account.
  Future<Result<IssuedSession>> signUpWithPassword({
    required String email,
    required String password,
  });
}
