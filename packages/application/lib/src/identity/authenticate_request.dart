import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Verifies a bearer token and reconciles the resulting principal against the
/// platform's canonical identity.users row.
final class AuthenticateRequest {
  const AuthenticateRequest(this._verifier, {UserDirectory? directory})
    : _directory = directory;

  final TokenVerifier _verifier;
  final UserDirectory? _directory;

  Future<Result<AuthenticatedUser>> call(String? authorizationHeader) async {
    final token = _extractBearer(authorizationHeader);
    if (token == null) {
      return const Result.err(
        AppError.authorization(
          'auth.missing_bearer',
          'Missing or malformed Authorization: Bearer token',
        ),
      );
    }

    final verified = await _verifier.verify(token);
    if (verified is Err<AuthenticatedUser>) return verified;
    final principal = (verified as Ok<AuthenticatedUser>).value;

    return _reconcile(principal);
  }

  Future<Result<AuthenticatedUser>> _reconcile(
    AuthenticatedUser principal,
  ) async {
    final directory = _directory;
    if (directory == null) return Result.ok(principal);
    if (principal.role == PlatformRole.service) return Result.ok(principal);

    final found = await directory.findUser(principal.userId);
    if (found is Err<User?>) return Result.err(found.error);
    final user = (found as Ok<User?>).value;
    if (user == null) return Result.ok(principal);

    if (!user.canAct) {
      return const Result.err(
        AppError.authorization(
          'auth.account_suspended',
          'This account is suspended',
        ),
      );
    }

    return Result.ok(
      AuthenticatedUser(
        userId: principal.userId,
        role: user.role,
        email: user.email ?? principal.email,
      ),
    );
  }

  static String? _extractBearer(String? header) {
    if (header == null) return null;
    final lower = header.toLowerCase();
    if (!lower.startsWith('bearer ')) return null;
    final token = header.substring('bearer '.length).trim();
    return token.isEmpty ? null : token;
  }
}
