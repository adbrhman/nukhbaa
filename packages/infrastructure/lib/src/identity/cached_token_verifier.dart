import 'package:application/application.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// Holds the tokens [TokenVerifier] has already accepted, each until its own
/// `exp` and never longer than `maxAge`.
///
/// Every authenticated request verified its bearer token from scratch: an
/// ES256 signature checked in pure Dart (PointyCastle), repeated for the same
/// token by every poll and screen of one session, on a server with 0.2 vCPU
/// (script 100). A token accepted once is accepted again from memory.
///
/// Only an accepted token is held: a malformed, forged, expired or
/// unverifiable one is checked again every time, and a token without `exp`
/// is never held. What a token grants does not change: the principal comes
/// from the token alone, a held token is refused from its `exp` on, and
/// `AuthenticateRequest` still reads the account's status on every request.
final class CachedTokenVerifier implements TokenVerifier {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedTokenVerifier(
    this._inner, {
    Duration maxAge = const Duration(minutes: 5),
    int maxEntries = 1024,
    DateTime Function() now = DateTime.now,
  }) : _now = now,
       _accepted = TtlCache<String, _Accepted>(
         ttl: maxAge,
         maxEntries: maxEntries,
         now: now,
       );

  final TokenVerifier _inner;
  final DateTime Function() _now;
  final TtlCache<String, _Accepted> _accepted;

  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) async {
    final _Accepted? held = _accepted.read(bearerToken);
    if (held != null && _now().isBefore(held.expiresAt)) {
      return Result.ok(held.principal);
    }
    final int startedAt = _accepted.generation;
    final Result<AuthenticatedUser> result = await _inner.verify(bearerToken);
    if (result case Ok<AuthenticatedUser>(
      value: final AuthenticatedUser principal,
    )) {
      final DateTime? expiresAt = _expiryOf(bearerToken);
      if (expiresAt != null && _now().isBefore(expiresAt)) {
        _accepted.write(
          bearerToken,
          _Accepted(principal, expiresAt),
          startedAt: startedAt,
        );
      }
    }
    return result;
  }

  /// The `exp` of a token [_inner] has just accepted, or `null` when absent.
  static DateTime? _expiryOf(String token) {
    try {
      final Object? payload = JWT.decode(token).payload;
      if (payload is! Map) return null;
      final Object? exp = payload['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        (exp * 1000).toInt(),
        isUtc: true,
      );
    } on Object {
      return null;
    }
  }
}

/// A principal accepted from a token, with the token's expiry.
final class _Accepted {
  const _Accepted(this.principal, this.expiresAt);

  final AuthenticatedUser principal;
  final DateTime expiresAt;
}
