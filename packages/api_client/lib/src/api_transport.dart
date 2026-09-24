import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/src/api_error.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// Supplies the bearer credential for a request, or `null` for an anonymous
/// call.
///
/// The Supabase access token is owned by the client app (the Auth phase), not
/// this transport — `api_client` never verifies, stores, or refreshes a token;
/// it only attaches whatever the app provides. Async so the app may read it
/// from secure storage / a refresh flow without this layer knowing how.
typedef TokenProvider = Future<String?> Function();

/// What a session renewal achieved, as reported by a [SessionRenewer].
enum SessionRenewal {
  /// A fresh access token is now stored; the request is worth repeating.
  renewed,

  /// The session cannot be renewed (no refresh token, or the identity
  /// provider refused it): the user has to sign in again.
  rejected,

  /// The renewal could not be attempted right now (offline, timeout): the
  /// session is kept, and the call fails as a retryable network error.
  unavailable,
}

/// Renews the session after a `401`. Owned by the app like [TokenProvider]:
/// this transport never stores or exchanges a token itself.
typedef SessionRenewer = Future<SessionRenewal> Function();

/// The single low-level HTTP transport every domain client is built on.
///
/// Responsibilities (and ONLY these — no business logic, ADR-002 §2.8):
///   * resolve a path against the configured [baseUri];
///   * attach `Authorization: Bearer <token>` (from [tokenProvider]) and
///     `Accept: application/json` / `Content-Type: application/json`;
///   * turn a JSON response into a decoded value via a caller-supplied parser;
///   * dispatch 2xx -> `Ok`, non-2xx -> `Err` (via [decodeError]), and any
///     transport exception -> a transient `Err` (via [networkError]);
///   * be **total** — every method returns a typed [Result] and never throws.
///
/// It holds an injected [http.Client] so tests can drive it with
/// `package:http/testing.dart`'s `MockClient` (a standard, accepted way to test
/// a transport layer — no live socket, no permanent mock in shipped code).
final class ApiTransport {
  /// Creates a transport rooted at [baseUri], using [httpClient] for I/O and
  /// [tokenProvider] to obtain the (optional) bearer token per request.
  ///
  /// [requestTimeout] bounds every individual HTTP call (default 15s; pass
  /// `null` to disable). Without it, `package:http`'s default `Client` has NO
  /// built-in timeout: a request that never receives a response (silent
  /// proxy/tunnel stall, dropped packets, a server that accepts the
  /// connection but never replies) hangs the awaiting `Future` forever, which
  /// — one layer up — leaves an `AsyncNotifier` stuck in its "in flight"
  /// state indefinitely (e.g. sign-in spinning forever with no error). A
  /// timeout here converts that silent hang into a `TimeoutException`, caught
  /// below and reported as the same transient, retryable [networkError] as
  /// any other transport failure — the "never throws" contract holds.
  ///
  /// `null` is for tests only: `Future.timeout()` schedules a real `Timer`
  /// even for a long duration, and a widget test that intentionally leaves a
  /// request unresolved (to assert a loading state) would otherwise fail
  /// Flutter's "no pending timers" teardown invariant. Every test harness
  /// wiring this transport over a `MockClient` passes `requestTimeout: null`
  /// explicitly; production wiring (`apps/mobile/lib/core/providers.dart`)
  /// leaves the 15s default in place.
  ///
  /// [onUnauthorized], if provided, is invoked whenever the server responds
  /// with `401` — the auth layer uses this hook to react to a revoked or
  /// expired session (e.g. force a sign-out) without this transport knowing
  /// anything about session/auth state itself.
  ///
  /// [renewSession], if provided, runs first on a `401` for a call made with
  /// the stored credential: a renewed session repeats the call once, a
  /// rejected one falls through to [onUnauthorized], and an unavailable one
  /// fails as a retryable network error without ending the session.
  ApiTransport({
    required Uri baseUri,
    required http.Client httpClient,
    required TokenProvider tokenProvider,
    Duration? requestTimeout = const Duration(seconds: 15),
    Future<void> Function()? onUnauthorized,
    SessionRenewer? renewSession,
  }) : _baseUri = baseUri,
       _httpClient = httpClient,
       _tokenProvider = tokenProvider,
       _requestTimeout = requestTimeout,
       _onUnauthorized = onUnauthorized,
       _renewSession = renewSession;

  final Uri _baseUri;
  final http.Client _httpClient;
  final TokenProvider _tokenProvider;
  final Duration? _requestTimeout;

  final Future<void> Function()? _onUnauthorized;

  final SessionRenewer? _renewSession;

  /// Performs `GET [path]` (with optional [query]) and decodes a JSON **object**
  /// body via [parse]. See [_send] for the total error contract.
  Future<Result<T>> getObject<T>(
    String path, {
    Map<String, String>? query,
    required T Function(Map<String, Object?> json) parse,
  }) {
    return _send<T>(
      method: 'GET',
      path: path,
      query: query,
      decode: (body) => _decodeObject(body, parse),
    );
  }

  /// Performs `GET [path]` (with optional [query]) and decodes a JSON body
  /// that is either an **object** (via [parse]) or a literal JSON `null` —
  /// for reads with no existence oracle where "nothing yet" is a legitimate
  /// `Ok(null)` rather than a `404` (e.g.
  /// `GET /competitions/{id}/seasons/current`, which returns `null` when no
  /// season currently covers "now" — the same philosophy as [getList]
  /// returning `[]`, not the "owned resource" philosophy of a `404`).
  Future<Result<T?>> getNullableObject<T>(
    String path, {
    Map<String, String>? query,
    required T Function(Map<String, Object?> json) parse,
  }) {
    return _send<T?>(
      method: 'GET',
      path: path,
      query: query,
      decode: (body) => _decodeNullableObject(body, parse),
    );
  }

  /// Performs `GET [path]` (with optional [query]) and decodes a JSON **array**
  /// body, mapping each element object via [parseElement].
  Future<Result<List<T>>> getList<T>(
    String path, {
    Map<String, String>? query,
    required T Function(Map<String, Object?> json) parseElement,
  }) {
    return _send<List<T>>(
      method: 'GET',
      path: path,
      query: query,
      decode: (body) => _decodeList(body, parseElement),
    );
  }

  /// Performs `POST [path]` with a JSON object [body] and decodes a JSON
  /// **object** response via [parse].
  Future<Result<T>> postObject<T>(
    String path, {
    required Map<String, Object?> body,
    required T Function(Map<String, Object?> json) parse,
  }) {
    return _send<T>(
      method: 'POST',
      path: path,
      requestBody: body,
      decode: (respBody) => _decodeObject(respBody, parse),
    );
  }

  /// Performs a JSON POST with an explicitly supplied bearer token.
  /// Used only for short-lived recovery credentials.
  Future<Result<T>> postObjectWithBearerToken<T>(
    String path, {
    required String bearerToken,
    required Map<String, Object?> body,
    required T Function(Map<String, Object?> json) parse,
  }) {
    return _send<T>(
      method: 'POST',
      path: path,
      requestBody: body,
      overrideToken: bearerToken,
      decode: (respBody) => _decodeObject(respBody, parse),
    );
  }

  /// Performs `PUT [path]` with a JSON object [body] and decodes a JSON
  /// **object** response via [parse]. Used for idempotent full-resource
  /// upserts (e.g. `PUT /fixtures/{id}`) — the same request pipeline and
  /// error contract as [postObject], differing only in HTTP verb.
  Future<Result<T>> putObject<T>(
    String path, {
    required Map<String, Object?> body,
    required T Function(Map<String, Object?> json) parse,
  }) {
    return _send<T>(
      method: 'PUT',
      path: path,
      requestBody: body,
      decode: (respBody) => _decodeObject(respBody, parse),
    );
  }

  /// Performs `DELETE [path]` (no request body) and decodes a JSON **object**
  /// response via [parse]. Used for idempotent resource removals (e.g.
  /// `DELETE /rounds/{id}/fixtures/{fixtureId}`) — the same request pipeline
  /// and error contract as [postObject]/[putObject], differing only in HTTP
  /// verb and having no request body.
  Future<Result<T>> deleteObject<T>(
    String path, {
    required T Function(Map<String, Object?> json) parse,
  }) {
    return _send<T>(
      method: 'DELETE',
      path: path,
      decode: (respBody) => _decodeObject(respBody, parse),
    );
  }

  /// The shared request pipeline. Builds the request, applies auth headers,
  /// executes it, and dispatches the response. Never throws: a transport
  /// exception becomes a transient [Result.err]; a non-2xx becomes a decoded
  /// [Result.err]; a 2xx with an undecodable body becomes a malformed-response
  /// [Result.err].
  /// Performs `POST [path]` with a raw byte body under [contentType] and
  /// decodes a JSON **object** response via [parse].
  ///
  /// The one non-JSON request this client makes. An image is payload, not a
  /// domain intent, so base64-ing it into an envelope would inflate every
  /// upload by a third to gain nothing; the content type is already a header.
  /// Everything else -- auth, timeout, 401 handling, error decoding -- is the
  /// shared pipeline, so this cannot drift from the rest of the client.
  Future<Result<T>> postBytes<T>(
    String path, {
    required List<int> bytes,
    required String contentType,
    required T Function(Map<String, Object?> json) parse,
  }) {
    return _send<T>(
      method: 'POST',
      path: path,
      requestBytes: bytes,
      requestContentType: contentType,
      decode: (respBody) => _decodeObject(respBody, parse),
    );
  }

  /// `GET` returning raw bytes rather than JSON -- the one response on this
  /// platform that is not a document: `GET /users/{id}/avatar`.
  ///
  /// `Ok(null)` for `404`, because a user with no stored picture is not an
  /// error; the caller draws their initial. Every other status goes through
  /// the shared error decoding, and a `401` still triggers the shared
  /// unauthorized hook, so an expired session logs out here exactly as it
  /// does on any other call.
  ///
  /// This exists so images travel the same authenticated pipeline as
  /// everything else. `Image.network`'s `headers` argument is silently
  /// dropped on Flutter web (the browser's own `<img>` loader fetches the
  /// URL), so a widget that reached for the network directly could not
  /// authenticate at all there.
  Future<Result<Uint8List?>> getBytes(String path) async {
    final sent = await _sendRenewing(
      path: path,
      send: () => _rawSend(method: 'GET', path: path),
    );
    if (sent is Err<http.Response>) return Result.err(sent.error);
    final response = (sent as Ok<http.Response>).value;
    final status = response.statusCode;
    if (status == 404) return const Result.ok(null);
    if (status >= 200 && status < 300) return Result.ok(response.bodyBytes);
    if (status == 401) {
      await _onUnauthorized?.call();
    }
    return Result.err(decodeError(status, response.body));
  }

  Future<Result<T>> _send<T>({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    List<int>? requestBytes,
    String? requestContentType,
    String? overrideToken,
    required Result<T> Function(String body) decode,
  }) async {
    Future<Result<http.Response>> once() => _rawSend(
      method: method,
      path: path,
      query: query,
      requestBody: requestBody,
      requestBytes: requestBytes,
      requestContentType: requestContentType,
      overrideToken: overrideToken,
    );
    final sent = await _sendRenewing(
      path: path,
      overrideToken: overrideToken,
      send: () async {
        final Result<http.Response> first = await once();
        // A GET that never reached the server is tried once more, at once.
        // Back from the background, the pooled keep-alive socket may have
        // been closed by the server's proxy meanwhile: the first request
        // dies on it, the second opens a fresh connection. GET only --
        // repeating it changes nothing server-side -- and never after a
        // timeout, which already waited its full length.
        if (method == 'GET' &&
            first is Err<http.Response> &&
            first.error.code == apiErrorNetworkUnreachable) {
          return once();
        }
        return first;
      },
    );
    if (sent is Err<http.Response>) return Result.err(sent.error);
    final response = (sent as Ok<http.Response>).value;

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return decode(response.body);
    }
    if (status == 401) {
      await _onUnauthorized?.call();
    }
    return Result.err(decodeError(status, response.body));
  }

  /// Sends via [send]; when that draws a `401` on a call made with the stored
  /// credential, asks [_renewSession] once for a fresh token and repeats the
  /// call. Auth routes and explicit-token calls are never renewed: the
  /// renewal itself goes through `/auth/refresh`, so this is also what keeps
  /// it from recursing.
  Future<Result<http.Response>> _sendRenewing({
    required String path,
    String? overrideToken,
    required Future<Result<http.Response>> Function() send,
  }) async {
    final Result<http.Response> first = await send();
    final SessionRenewer? renew = _renewSession;
    if (renew == null || overrideToken != null || path.startsWith('/auth/')) {
      return first;
    }
    if (first case Ok<http.Response>(
      :final value,
    ) when value.statusCode == 401) {
      switch (await renew()) {
        case SessionRenewal.renewed:
          return send();
        case SessionRenewal.unavailable:
          return Result.err(networkError('session renewal unavailable'));
        case SessionRenewal.rejected:
          return first;
      }
    }
    return first;
  }

  // The wire itself: URL, headers, method, timeout. Status interpretation is
  // deliberately NOT here -- a bytes response and a JSON response disagree
  // about what 404 means, and folding that into the sender would force one of
  // them to lie.
  Future<Result<http.Response>> _rawSend({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    List<int>? requestBytes,
    String? requestContentType,
    String? overrideToken,
  }) async {
    final uri = _resolve(path, query);

    final http.Response response;
    try {
      final headers = await _headers(
        hasBody: requestBody != null,
        contentType: requestContentType,
        overrideToken: overrideToken,
      );
      final pending = switch (method) {
        'GET' => _httpClient.get(uri, headers: headers),
        // A byte body wins when present: the two are never both set, and
        // jsonEncode(null) would otherwise send the string "null".
        'POST' => _httpClient.post(
          uri,
          headers: headers,
          body: requestBytes ?? jsonEncode(requestBody),
        ),
        'PUT' => _httpClient.put(
          uri,
          headers: headers,
          body: jsonEncode(requestBody),
        ),
        'DELETE' => _httpClient.delete(uri, headers: headers),
        _ => throw ArgumentError.value(method, 'method', 'unsupported'),
      };
      final timeout = _requestTimeout;
      response = timeout == null
          ? await pending
          : await pending.timeout(timeout);
    } on TimeoutException catch (cause) {
      // The request's `.timeout(_requestTimeout)` elapsed with no response —
      // distinguished from other transport failures so the UI can tell the
      // user the server didn't answer in time (vs. being unreachable).
      return Result.err(timeoutError(cause));
    } on Object catch (cause) {
      // DNS failure, socket reset, closed client, etc. — never reached the
      // server (or never got a response): a transient, retryable failure.
      return Result.err(networkError(cause));
    }

    return Result.ok(response);
  }

  Uri _resolve(String path, Map<String, String>? query) {
    // Preserve any base path prefix (e.g. a reverse-proxy mount) by joining
    // rather than replacing. `path` is always server-relative (no leading
    // scheme) and starts with '/'.
    final base = _baseUri.path.endsWith('/')
        ? _baseUri
        : _baseUri.replace(path: '${_baseUri.path}/');
    final merged = base.resolve(
      path.startsWith('/') ? path.substring(1) : path,
    );
    if (query == null || query.isEmpty) return merged;
    return merged.replace(
      queryParameters: {...merged.queryParameters, ...query},
    );
  }

  Future<Map<String, String>> _headers({
    required bool hasBody,
    String? contentType,
    String? overrideToken,
  }) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (contentType != null) {
      headers['content-type'] = contentType;
    } else if (hasBody) {
      headers['content-type'] = 'application/json';
    }
    final token = overrideToken ?? await _tokenProvider();

    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Result<T> _decodeObject<T>(
    String body,
    T Function(Map<String, Object?> json) parse,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return Result.err(
          malformedResponse(
            'expected a JSON object, got ${decoded.runtimeType}',
          ),
        );
      }
      return Result.ok(parse(decoded.cast<String, Object?>()));
    } on Object catch (cause) {
      return Result.err(malformedResponse(cause));
    }
  }

  static Result<T?> _decodeNullableObject<T>(
    String body,
    T Function(Map<String, Object?> json) parse,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded == null) return const Result.ok(null);
      if (decoded is! Map) {
        return Result.err(
          malformedResponse(
            'expected a JSON object or null, got ${decoded.runtimeType}',
          ),
        );
      }
      return Result.ok(parse(decoded.cast<String, Object?>()));
    } on Object catch (cause) {
      return Result.err(malformedResponse(cause));
    }
  }

  static Result<List<T>> _decodeList<T>(
    String body,
    T Function(Map<String, Object?> json) parseElement,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        return Result.err(
          malformedResponse(
            'expected a JSON array, got ${decoded.runtimeType}',
          ),
        );
      }
      final out = <T>[];
      for (final element in decoded) {
        if (element is! Map) {
          return Result.err(
            malformedResponse(
              'expected each array element to be a JSON object, '
              'got ${element.runtimeType}',
            ),
          );
        }
        out.add(parseElement(element.cast<String, Object?>()));
      }
      return Result.ok(out);
    } on Object catch (cause) {
      return Result.err(malformedResponse(cause));
    }
  }
}
