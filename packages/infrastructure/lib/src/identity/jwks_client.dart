import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

final class Jwk {
  Jwk(this.raw) : kid = raw['kid'] as String?;
  final String? kid;
  final Map<String, dynamic> raw;
}

final class JwksClient {
  JwksClient(
    this.jwksUri, {
    http.Client? httpClient,
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 10),
    this.minRefreshInterval = const Duration(seconds: 30),
    this.fetchTimeout = const Duration(seconds: 5),
  }) : _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now;

  final Uri jwksUri;
  final Duration ttl;
  final Duration minRefreshInterval;
  final Duration fetchTimeout;

  final http.Client _http;
  final DateTime Function() _now;

  Map<String, Jwk> _byKid = const {};
  List<Jwk> _keyless = const [];
  DateTime? _fetchedAt;
  DateTime? _lastRefreshAttempt;

  /// Eagerly populates the key cache at server startup (composition root
  /// bootstrap), so the very first authenticated request resolves a `kid`
  /// from the in-memory cache with no network call on the request's hot path.
  Future<Result<void>> warmUp() => _refresh();

  /// The in-flight refresh, shared by concurrent callers.
  Future<Result<void>>? _inFlight;

  Future<Result<Jwk>> keyForKid(String? kid) async {
    if (_isStale()) {
      final refreshed = await _refresh();
      if (refreshed is Err<void>) return Result.err(refreshed.error);
    }

    final hit = _lookup(kid);
    if (hit != null) return Result.ok(hit);

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

  void close() => _http.close();
}
