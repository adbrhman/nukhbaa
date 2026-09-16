import 'dart:async';
import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// [FootballDataProvider] over football-data.org (API v4, free tier).
///
/// * **Competitions** are asked for by code (`PL`, `CL`, `BL1`, `PD`, `SA`).
/// * **Rate limit:** the free tier allows 10 calls a minute and no daily
///   cap, so this adapter spaces its calls at least [minimumGap] apart
///   (process-wide) and treats a 429 as [providerQuotaErrorCode].
/// * **Days:** the API filters by UTC date, so a Riyadh day (UTC+3) is asked
///   for as the UTC dates it spans and the matches are then kept by their
///   Riyadh day.
/// * **Scores:** the result recorded is the score after extra time, never
///   including a shoot-out. For a match decided on penalties it is
///   `regularTime + extraTime` when present, else `fullTime - penalties`;
///   when neither can be derived the match is not given a result.
///
/// Never throws.
final class FootballDataOrgProvider implements FootballDataProvider {
  /// Creates the adapter.
  FootballDataOrgProvider({
    required String apiKey,
    http.Client? httpClient,
    this.minimumGap = const Duration(milliseconds: 6500),
    Uri? baseUri,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _apiKey = apiKey,
       _http = httpClient ?? http.Client(),
       _base = baseUri ?? Uri.parse('https://api.football-data.org'),
       _sleep = sleep ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final String _apiKey;
  final http.Client _http;
  final Uri _base;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  /// Minimum time between two calls.
  final Duration minimumGap;

  DateTime? _lastCall;
  Future<void> _queue = Future<void>.value();

  static const String _userAgent =
      'Nukhbaa/1.0 (+https://adbrhman.github.io/nukhbaa/)';
  static const Duration _timeout = Duration(seconds: 20);

  @override
  Future<Result<List<ProviderMatch>>> matchesOn({
    required String leagueExternalId,
    required DateTime riyadhDay,
  }) {
    // Serialise calls so the spacing holds even if two jobs overlap.
    final completer = Completer<Result<List<ProviderMatch>>>();
    _queue = _queue.then((_) async {
      completer.complete(await _fetch(leagueExternalId, riyadhDay));
    });
    return completer.future;
  }

  Future<Result<List<ProviderMatch>>> _fetch(
    String code,
    DateTime riyadhDay,
  ) async {
    final last = _lastCall;
    if (last != null) {
      final wait = minimumGap - _now().difference(last);
      if (wait > Duration.zero) {
        await _sleep(wait);
      }
    }
    _lastCall = _now();

    final day = DateTime.utc(riyadhDay.year, riyadhDay.month, riyadhDay.day);
    final uri = _base.replace(
      path: '/v4/competitions/$code/matches',
      queryParameters: {
        'dateFrom': isoDay(day.subtract(const Duration(days: 1))),
        'dateTo': isoDay(day),
      },
    );

    final http.Response response;
    try {
      response = await _http
          .get(
            uri,
            headers: {
              'X-Auth-Token': _apiKey,
              'User-Agent': _userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on Object catch (error) {
      return Result.err(
        AppError.transient(
          'football_data.provider_unreachable',
          'football-data.org request failed',
          error,
        ),
      );
    }

    if (response.statusCode == 429) {
      return const Result.err(
        AppError.transient(
          providerQuotaErrorCode,
          'football-data.org rate limit reached',
        ),
      );
    }
    if (response.statusCode != 200) {
      return Result.err(
        AppError.transient(
          'football_data.provider_http_${response.statusCode}',
          'football-data.org answered ${response.statusCode}',
        ),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      return Result.err(
        AppError.transient(
          'football_data.provider_malformed',
          'football-data.org returned invalid JSON',
          error,
        ),
      );
    }
    final rows = decoded is Map<String, Object?> ? decoded['matches'] : null;
    if (rows is! List<Object?>) {
      return const Result.err(
        AppError.transient(
          'football_data.provider_malformed',
          'football-data.org response has no matches list',
        ),
      );
    }

    return Result.ok([
      for (final raw in rows)
        if (raw is Map<String, Object?>)
          if (parseMatch(raw, code) case final ProviderMatch match)
            if (riyadhDayOf(match.kickoffAt) == day) match,
    ]);
  }

  /// Maps one football-data.org match; null when an essential field is
  /// missing.
  static ProviderMatch? parseMatch(Map<String, Object?> json, String code) {
    final id = json['id'];
    final utcDate = json['utcDate'];
    final home = json['homeTeam'];
    final away = json['awayTeam'];
    if (id == null ||
        utcDate is! String ||
        home is! Map<String, Object?> ||
        away is! Map<String, Object?> ||
        home['id'] == null ||
        away['id'] == null) {
      return null;
    }
    final kickoff = DateTime.tryParse(utcDate);
    if (kickoff == null) {
      return null;
    }
    final status = statusOf(
      json['status'] is String ? json['status']! as String : '',
    );
    final goals = status == ProviderMatchStatus.finished
        ? finalScore(json['score'])
        : null;
    return ProviderMatch(
      externalId: id.toString(),
      leagueExternalId: code,
      homeTeamExternalId: home['id'].toString(),
      awayTeamExternalId: away['id'].toString(),
      homeTeamName: home['name'] is String ? home['name']! as String : '',
      awayTeamName: away['name'] is String ? away['name']! as String : '',
      kickoffAt: kickoff.toUtc(),
      status: status,
      homeGoals: goals?.$1,
      awayGoals: goals?.$2,
    );
  }

  /// Maps a football-data.org match status.
  static ProviderMatchStatus statusOf(String status) {
    switch (status.trim().toUpperCase()) {
      case 'SCHEDULED':
      case 'TIMED':
        return ProviderMatchStatus.scheduled;
      case 'IN_PLAY':
      case 'PAUSED':
      case 'LIVE':
        return ProviderMatchStatus.live;
      case 'FINISHED':
        return ProviderMatchStatus.finished;
      case 'POSTPONED':
        return ProviderMatchStatus.postponed;
      case 'SUSPENDED':
      case 'CANCELLED':
      case 'AWARDED':
        return ProviderMatchStatus.cancelled;
      default:
        return ProviderMatchStatus.unknown;
    }
  }

  /// The score after extra time, shoot-out excluded; null when it cannot be
  /// derived safely.
  static (int, int)? finalScore(Object? score) {
    if (score is! Map<String, Object?>) {
      return null;
    }
    final fullTime = _pair(score['fullTime']);
    final duration = score['duration'];
    if (duration != 'PENALTY_SHOOTOUT') {
      return fullTime;
    }
    final regular = _pair(score['regularTime']);
    final extra = _pair(score['extraTime']);
    if (regular != null && extra != null) {
      return (regular.$1 + extra.$1, regular.$2 + extra.$2);
    }
    final penalties = _pair(score['penalties']);
    if (fullTime != null && penalties != null) {
      final home = fullTime.$1 - penalties.$1;
      final away = fullTime.$2 - penalties.$2;
      if (home >= 0 && away >= 0) {
        return (home, away);
      }
    }
    return null;
  }

  static (int, int)? _pair(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final home = raw['home'];
    final away = raw['away'];
    if (home is int && away is int) {
      return (home, away);
    }
    return null;
  }
}
