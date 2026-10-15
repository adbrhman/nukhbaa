import 'dart:convert';

import 'package:application/application.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// [PushSender] over FCM HTTP v1.
///
/// The whole OAuth dance is four lines of intent: sign a JWT with the service
/// account's RSA key, hand it to Google's token endpoint, get an access token,
/// send. `dart_jsonwebtoken` (already a dependency, used by the Supabase
/// verifier) does the RS256 signing, so no new package is needed.
///
/// The access token is cached until shortly before it expires -- FCM is called
/// once per reminder sweep, and minting a token per message would be a
/// self-inflicted rate limit.
///
/// Messages go out [parallelMessages] at a time (audit M-32): one after the
/// other, a broadcast or a popular match's winners kept the request that
/// scored it waiting past the app's 35-second timeout.
///
/// Never throws: a transport failure is a typed [Result], and a per-token
/// rejection is reported through the returned dead-token list.
final class FcmPushSender implements PushSender {
  /// Creates the sender over a parsed service-account map.
  FcmPushSender({
    required Map<String, Object?> serviceAccount,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _serviceAccount = serviceAccount,
       _http = httpClient ?? http.Client(),
       _requestTimeout = requestTimeout;

  /// Parses the service-account JSON (the Northflank environment variable).
  ///
  /// Returns `null` when [raw] is absent or unusable, so the caller can fall
  /// back to a no-op sender rather than refusing to boot: a server that cannot
  /// push is degraded, not broken (Tier-3, ADR 0007 §2.4).
  static FcmPushSender? tryParse(String? raw, {http.Client? httpClient}) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      for (final key in const ['project_id', 'client_email', 'private_key']) {
        if (decoded[key] is! String) {
          return null;
        }
      }
      return FcmPushSender(serviceAccount: decoded, httpClient: httpClient);
    } on Object {
      return null;
    }
  }

  final Map<String, Object?> _serviceAccount;
  final http.Client _http;

  /// How long one call to Google may take before it is abandoned.
  ///
  /// `http` applies no timeout of its own, so a connection that never
  /// answered held its caller forever -- and the callers are ScoreFixture
  /// (winner pushes, awaited before it returns) and every push sweep. One
  /// silent socket froze the automatic results sync until a restart.
  final Duration _requestTimeout;

  static const String _tokenUri = 'https://oauth2.googleapis.com/token';
  static const String _scope =
      'https://www.googleapis.com/auth/firebase.messaging';

  String? _accessToken;
  DateTime? _accessTokenExpiry;

  String get _projectId => _serviceAccount['project_id']! as String;

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    if (tokens.isEmpty) {
      return const Result.ok(<String>[]);
    }

    final tokenResult = await _authorize();
    if (tokenResult is Err<String>) {
      return Result.err(tokenResult.error);
    }
    final accessToken = (tokenResult as Ok<String>).value;

    final endpoint = Uri.parse(
      'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
    );
    final dead = <String>[];
    var delivered = 0;
    var failed = 0;

    Future<_Outcome> sendOne(String token) async {
      try {
        final response = await _http
            .post(
              endpoint,
              headers: {
                'Authorization': 'Bearer $accessToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'message': {
                  'token': token,
                  'notification': {'title': title, 'body': body},
                  if (link != null) 'data': {'link': link},
                  'android': {'priority': 'HIGH'},
                },
              }),
            )
            .timeout(_requestTimeout);
        if (response.statusCode == 200) {
          return _Outcome.delivered;
        }
        if (_isPermanentlyInvalid(response.statusCode, response.body)) {
          return _Outcome.dead;
        }
        // Anything else (429, 5xx) is transient: the token stays --
        // retiring it here would unsubscribe a real user over a blip.
        return _Outcome.failed;
      } on Object {
        // A network failure on one message must not abandon the rest.
        return _Outcome.failed;
      }
    }

    for (var start = 0; start < tokens.length; start += parallelMessages) {
      final List<String> batch = tokens.sublist(
        start,
        start + parallelMessages > tokens.length
            ? tokens.length
            : start + parallelMessages,
      );
      final List<_Outcome> outcomes = await Future.wait(batch.map(sendOne));
      // In token order, so the dead list reads as the tokens were given.
      for (var i = 0; i < batch.length; i++) {
        switch (outcomes[i]) {
          case _Outcome.delivered:
            delivered++;
          case _Outcome.dead:
            dead.add(batch[i]);
          case _Outcome.failed:
            failed++;
        }
      }
    }

    // Nothing reached a phone, and at least one message failed for a
    // reason that may pass (429, 5xx, a network error or timeout): an
    // error, so the sweeps do not record this push as sent and try again
    // on their next tick. As an `Ok` it was marked sent and lost -- a short
    // FCM outage cost a whole day's reminders, unseen (audit M-28).
    if (delivered == 0 && failed > 0) {
      return Result.err(
        AppError.transient(
          'push.not_delivered',
          'No message reached FCM: $failed failed, ${dead.length} retired',
        ),
      );
    }
    return Result.ok(dead);
  }

  /// Messages sent to FCM at the same time.
  static const int parallelMessages = 10;

  // 404 UNREGISTERED = the app was uninstalled or the token rotated.
  // 400 INVALID_ARGUMENT on the token field = a malformed token.
  // 403 SENDER_ID_MISMATCH = a token of another Firebase project; retried,
  // it would fail every sweep for ever now that a push nobody got is an
  // error (M-28).
  bool _isPermanentlyInvalid(int status, String body) {
    if (status == 404) {
      return true;
    }
    if (status == 403) {
      return body.contains('SENDER_ID_MISMATCH');
    }
    if (status != 400) {
      return false;
    }
    return body.contains('INVALID_ARGUMENT') && body.contains('token');
  }

  Future<Result<String>> _authorize() async {
    final cached = _accessToken;
    final expiry = _accessTokenExpiry;
    final now = DateTime.now().toUtc();
    if (cached != null &&
        expiry != null &&
        expiry.isAfter(now.add(const Duration(minutes: 1)))) {
      return Result.ok(cached);
    }

    final String assertion;
    try {
      final jwt = JWT({
        'iss': _serviceAccount['client_email']! as String,
        'scope': _scope,
        'aud': _tokenUri,
      });
      assertion = jwt.sign(
        RSAPrivateKey(_serviceAccount['private_key']! as String),
        algorithm: JWTAlgorithm.RS256,
        expiresIn: const Duration(hours: 1),
      );
    } on Object catch (error) {
      return Result.err(
        AppError.transient(
          'push.credentials_unusable',
          'Could not sign the service-account assertion',
          error,
        ),
      );
    }

    try {
      final response = await _http
          .post(
            Uri.parse(_tokenUri),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
              'assertion': assertion,
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return Result.err(
          AppError.transient(
            'push.token_exchange_failed',
            'Google refused the assertion (${response.statusCode})',
          ),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?> ||
          decoded['access_token'] is! String) {
        return const Result.err(
          AppError.transient(
            'push.token_exchange_failed',
            'The token response had no access_token',
          ),
        );
      }
      final seconds = decoded['expires_in'];
      _accessToken = decoded['access_token']! as String;
      _accessTokenExpiry = now.add(
        Duration(seconds: seconds is int ? seconds : 3600),
      );
      return Result.ok(_accessToken!);
    } on Object catch (error) {
      return Result.err(
        AppError.transient(
          'push.token_exchange_failed',
          'Could not reach the Google token endpoint',
          error,
        ),
      );
    }
  }
}

/// What became of one message.
enum _Outcome { delivered, dead, failed }

/// The [PushSender] used when no service account is configured.
///
/// Reports every token as delivered and none as dead, so a server without
/// Firebase credentials still boots, still runs the sweep, and never retires a
/// token it could not actually try.
final class NoopPushSender implements PushSender {
  /// Creates the no-op sender.
  const NoopPushSender();

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async => const Result.ok(<String>[]);
}
