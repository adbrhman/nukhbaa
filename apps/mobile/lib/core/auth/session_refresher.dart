/// Silent session renewal: an expired access token becomes one
/// `POST /auth/refresh` and a repeated request, instead of the sign-in
/// screen.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

import 'token_store.dart';

/// Exchanges the stored refresh token for a new session, one exchange at a
/// time.
///
/// Concurrent `401`s (a screen firing several requests as the token ages
/// out) share one in-flight exchange: the identity provider rotates the
/// refresh token on every use and treats a reuse outside a short window as
/// theft, so a second parallel exchange could end the session.
final class SessionRefresher {
  /// Creates a refresher over [store], renewing through [refresh].
  SessionRefresher({
    required TokenStore store,
    required Future<Result<AuthResponseDto>> Function(String refreshToken)
    refresh,
  }) : _store = store,
       _refresh = refresh;

  final TokenStore _store;
  final Future<Result<AuthResponseDto>> Function(String refreshToken) _refresh;
  Future<SessionRenewal>? _inFlight;

  /// Renews the session; see [SessionRenewal] for what each outcome means.
  Future<SessionRenewal> call() =>
      _inFlight ??= _renew().whenComplete(() => _inFlight = null);

  Future<SessionRenewal> _renew() async {
    try {
      final String? refreshToken = await _store.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return SessionRenewal.rejected;
      }
      final Result<AuthResponseDto> result = await _refresh(refreshToken);
      switch (result) {
        case Ok<AuthResponseDto>(:final value):
          final String? accessToken = value.accessToken;
          if (accessToken == null || accessToken.isEmpty) {
            return SessionRenewal.rejected;
          }
          await _store.write(accessToken);
          final String? next = value.refreshToken;
          if (next != null && next.isNotEmpty) {
            await _store.writeRefreshToken(next);
          }
          return SessionRenewal.renewed;
        case Err<AuthResponseDto>(:final error):
          // Offline or a server blip: keep the session and let the call fail
          // as retryable. Anything else is the provider refusing the token.
          return error.kind == ErrorKind.transient
              ? SessionRenewal.unavailable
              : SessionRenewal.rejected;
      }
    } on Object {
      // The secure store failed mid-renewal; the session is left as it was.
      return SessionRenewal.unavailable;
    }
  }
}

/// Builds the app's shared [ApiTransport]: the bearer comes from [store],
/// and a `401` first tries a silent renewal through `POST /auth/refresh`.
/// Only when the renewal is refused does [onSessionEnded] run (sign-out).
ApiTransport buildSessionTransport({
  required Uri baseUri,
  required http.Client httpClient,
  required TokenStore store,
  required Future<void> Function() onSessionEnded,
  Duration? requestTimeout = const Duration(seconds: 35),
}) {
  late final ApiTransport transport;
  final SessionRefresher refresher = SessionRefresher(
    store: store,
    refresh: (refreshToken) =>
        AuthApi(transport).refresh(refreshToken: refreshToken),
  );
  transport = ApiTransport(
    baseUri: baseUri,
    httpClient: httpClient,
    tokenProvider: store.read,
    requestTimeout: requestTimeout,
    renewSession: refresher.call,
    onUnauthorized: onSessionEnded,
  );
  return transport;
}
