import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// A single JSON Web Key as returned by the Supabase JWKS endpoint, retaining
/// the raw map so it can be handed to `JWTKey.fromJWK` unchanged, plus the
/// `kid` used for selection.
final class Jwk {
  /// Wraps a raw JWK map, extracting its `kid`.
  Jwk(this.raw) : kid = raw['kid'] as String?;

  /// The key id used to match a token header's `kid`, or `null` if the key
  /// carried none (in which case it participates only in fallback matching).
  final String? kid;

  /// The raw JWK JSON object (`kty`, `crv`, `x`, `y`, `kid`, `alg`, ...).
  final Map<String, dynamic> raw;
}

/// Fetches and caches a Supabase project's JWKS for local ES256 verification.
///
/// * Keys are cached for a bounded [ttl] (default 10 minutes).
/// * A lookup for a `kid` absent from the cache triggers at most one refresh
///   (rate-limited by [minRefreshInterval]).
/// * Every fetch is bounded by [fetchTimeout]; without it, a hung provider
///   stalls every authenticated request indefinitely.
/// * Concurrent refreshes are coalesced onto a single in-flight fetch, so a
///   stale cache does not trigger a thundering herd of simultaneous HTTP
///   calls against the provider.
final class JwksClient {
  /// Creates a JWKS client for [jwksUri].
  ///
  /// [httpClient] defaults to a fresh [http.Client]; tests inject a fake.
  /// [now] defaults to [DateTime.now]; tests inject a controllable clock.
  JwksClient(
    this.jwksUri, {
    http.Client? httpClient,
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 10),
    this.minRefreshInterval = const Duration(seconds: 30),
    this.fetchTimeout = const Duration(seconds: 5),
  }) : _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now;

  /// The project JWKS endpoint.
  final Uri jwksUri;

  /// How long a fetched key set is considered fresh.
  final Duration ttl;

  /// The minimum spacing between forced refreshes triggered by an unknown
  /// `kid`, bounding fetch amplification from bogus key ids.
  final Duration minRefreshInterval;

  /// How long to wait for the JWKS endpoint before giving up.
  final Duration fetchTimeout;

  final http.Client _http;
  final DateTime Function() _now;

  Map<String, Jwk> _byKid = const {};
  List<Jwk> _keyless = const [];
  DateTime? _fetchedAt;
  DateTime? _lastRefreshAttempt;

  /// The in-flight refresh, shared by concurrent callers. Only the initiator
  /// clears this slot when the fetch completes.
  Future<Result<void>>? _inFlight;

  /// Resolves the JWK matching [kid], fetching or refreshing as needed.
  Future<Result<Jwk>> keyForKid(String? kid) async {
    if (_isStale()) {
      final refreshed = await _refresh();
      if (refreshed is Err<void>) return Result.err(refreshed.error);
    }

    final hit = _lookup(kid);
    if (hit != null) return Result.ok(hit);

    // Cache miss: the signing key may have just rotated in. Force one
    // refresh, rate-limited, then retry once.
    if (_mayForceRefresh()) {
      final refreshed = await _refresh();
      if (refreshed is Err<void>) return Result.err(refreshed.error);
      final retry = _lookup(kid);
      if (retry != null) return Result.ok(retry);
    }

    return const Result.err(
      AppError.authorization(
        'auth.no_matching_key',
        'No JWKS key matches the token key id',
      ),
    );
  }

  Jwk? _lookup(String? kid) {
    if (kid != null) {
      final byKid = _byKid[kid];
      if (byKid != null) return byKid;
      return null;
    }
    if (_byKid.length == 1 && _keyless.isEmpty) return _byKid.values.first;
    if (_byKid.isEmpty && _keyless.length == 1) return _keyless.first;
    return null;
  }

  bool _isStale() {
    final fetchedAt = _fetchedAt;
    if (fetchedAt == null) return true;
    return _now().difference(fetchedAt) >= ttl;
  }

  bool _mayForceRefresh() {
    final last = _lastRefreshAttempt;
    if (last == null) return true;
    return _now().difference(last) >= minRefreshInterval;
  }

  /// Coalesces concurrent refreshes onto a single fetch. Without this, every
  /// request that arrives once the cache goes stale (or misses on an unknown
  /// `kid`) issues its own HTTP call — a thundering herd against the
  /// provider at exactly the moment verification is already degraded.
  Future<Result<void>> _refresh() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final pending = _fetchAndCache();
    _inFlight = pending;
    return pending.whenComplete(() {
      if (identical(_inFlight, pending)) _inFlight = null;
    });
  }

  Future<Result<void>> _fetchAndCache() async {
    _lastRefreshAttempt = _now();
    final http.Response response;
    try {
      response = await _http.get(jwksUri).timeout(fetchTimeout);
    } on Object catch (e) {
      return Result.err(
        AppError.transient('auth.jwks_fetch_failed', 'JWKS fetch failed', e),
      );
    }

    if (response.statusCode != 200) {
      return Result.err(
        AppError.transient(
          'auth.jwks_status',
          'JWKS endpoint returned ${response.statusCode}',
        ),
      );
    }

    final Map<String, Jwk> byKid;
    final List<Jwk> keyless;
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final keys = (decoded['keys'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Jwk.new)
          .toList(growable: false);
      byKid = {
        for (final k in keys)
          if (k.kid != null) k.kid!: k,
      };
      keyless = keys.where((k) => k.kid == null).toList(growable: false);
    } on Object catch (e) {
      return Result.err(
        AppError.transient('auth.jwks_parse_failed', 'JWKS parse failed', e),
      );
    }

    _byKid = byKid;
    _keyless = keyless;
    _fetchedAt = _now();
    return const Result.ok(null);
  }

  /// Releases the underlying HTTP client. Called on graceful shutdown.
  void close() => _http.close();
}
