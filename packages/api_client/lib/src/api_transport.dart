import 'dart:async';
import 'dart:convert';

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
  ApiTransport({
    required Uri baseUri,
    required http.Client httpClient,
    required TokenProvider tokenProvider,
    Duration? requestTimeout = const Duration(seconds: 15),
    Future<void> Function()? onUnauthorized,
  }) : _baseUri = baseUri,
       _httpClient = httpClient,
       _tokenProvider = tokenProvider,
       _requestTimeout = requestTimeout,
       _onUnauthorized = onUnauthorized;

  final Uri _baseUri;
  final http.Client _httpClient;
  final TokenProvider _tokenProvider;
  final Duration? _requestTimeout;

  final Future<void> Function()? _onUnauthorized;

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
  Future<Result<T>> _send<T>({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, Object?>? requestBody,
    required Result<T> Function(String body) decode,
  }) async {
    final uri = _resolve(path, query);

    final http.Response response;
    try {
      final headers = await _headers(hasBody: requestBody != null);
      final pending = switch (method) {
        'GET' => _httpClient.get(uri, headers: headers),
        'POST' => _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(requestBody),
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

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return decode(response.body);
    }
    if (status == 401) {
      await _onUnauthorized?.call();
    }
    return Result.err(decodeError(status, response.body));
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

  Future<Map<String, String>> _headers({required bool hasBody}) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (hasBody) headers['content-type'] = 'application/json';
    final token = await _tokenProvider();
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
