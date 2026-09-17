import 'dart:async';
import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// [FootballDataProvider] over the Highlightly football API
/// (`https://soccer.highlightly.net`, direct plan -- not RapidAPI).
///
/// * **Identity:** requests carry an explicit User-Agent; Cloudflare in front
///   of the API rejects HTTP-library defaults (error 1010).
/// * **Quota:** the free plan allows 100 requests a day. The provider reports
///   what is left in `x-ratelimit-requests-remaining`; once it drops to
///   [quotaReserve] this adapter stops calling and returns
///   [providerQuotaErrorCode], so results for today's matches always have
///   room. A 429 is treated the same way.
/// * **Days:** a day is asked for in Riyadh time (`timezone=Asia/Riyadh`), the
///   day the app's users live in; kickoffs come back as UTC instants.
/// * **Scores:** `state.score.current` (`"2 - 1"`) is the score after extra
///   time; a shoot-out is reported separately and is never part of it.
///
/// Never throws.
final class HighlightlyFootballDataProvider implements FootballDataProvider {
  /// Creates the adapter.
  HighlightlyFootballDataProvider({
    required String apiKey,
    http.Client? httpClient,
    this.quotaReserve = 25,
    Uri? baseUri,
  }) : _apiKey = apiKey,
       _http = httpClient ?? http.Client(),
       _base = baseUri ?? Uri.parse('https://soccer.highlightly.net');

  final String _apiKey;
  final http.Client _http;
  final Uri _base;

  /// Requests kept in hand before this adapter stops calling.
  final int quotaReserve;

  int? _remaining;

  /// The provider's last reported remaining daily requests, if any.
  int? get remainingRequests => _remaining;

  static const String _userAgent =
      'Nukhbaa/1.0 (+https://adbrhman.github.io/nukhbaa/)';
  static const Duration _timeout = Duration(seconds: 20);

  @override
  Future<Result<List<ProviderMatch>>> matchesOn({
    required String leagueExternalId,
    required DateTime riyadhDay,
  }) async {
    final left = _remaining;
    if (left != null && left <= quotaReserve) {
      return Result.err(
        AppError.transient(
          providerQuotaErrorCode,
          'Keeping the last $left provider requests in reserve',
        ),
      );
    }

    final uri = _base.replace(
      path: '/matches',
      queryParameters: {
        'leagueId': leagueExternalId,
        'date': isoDay(riyadhDay),
        'timezone': 'Asia/Riyadh',
        'limit': '100',
      },
    );

    final http.Response response;
    try {
      response = await _http
          .get(
            uri,
            headers: {
              'x-rapidapi-key': _apiKey,
              'User-Agent': _userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on Object catch (error) {
      return Result.err(
        AppError.transient(
          'football_data.provider_unreachable',
          'Highlightly request failed',
          error,
        ),
      );
    }

    final reported = int.tryParse(
      response.headers['x-ratelimit-requests-remaining'] ?? '',
    );
    if (reported != null) {
      _remaining = reported;
    }

    if (response.statusCode == 429) {
      _remaining = 0;
      return const Result.err(
        AppError.transient(
          providerQuotaErrorCode,
          'Highlightly daily quota exhausted',
        ),
      );
    }
    if (response.statusCode != 200) {
      return Result.err(
        AppError.transient(
          'football_data.provider_http_${response.statusCode}',
          'Highlightly answered ${response.statusCode}',
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
          'Highlightly returned invalid JSON',
          error,
        ),
      );
    }
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    if (data is! List<Object?>) {
      return const Result.err(
        AppError.transient(
          'football_data.provider_malformed',
          'Highlightly response has no data list',
        ),
      );
    }

    return Result.ok([
      for (final raw in data)
        if (raw is Map<String, Object?>)
          if (parseMatch(raw) case final ProviderMatch match) match,
    ]);
  }

  /// Maps one Highlightly match object; null when an essential field is
  /// missing (such a match is simply ignored).
  static ProviderMatch? parseMatch(Map<String, Object?> json) {
    final id = json['id'];
    final league = json['league'];
    final home = json['homeTeam'];
    final away = json['awayTeam'];
    final date = json['date'];
    if (id == null ||
        league is! Map<String, Object?> ||
        home is! Map<String, Object?> ||
        away is! Map<String, Object?> ||
        date is! String) {
      return null;
    }
    final kickoff = DateTime.tryParse(date);
    if (kickoff == null ||
        league['id'] == null ||
        home['id'] == null ||
        away['id'] == null) {
      return null;
    }

    final state = json['state'];
    final description = state is Map<String, Object?>
        ? _text(state['description'])
        : '';
    final score = state is Map<String, Object?> ? state['score'] : null;
    final current = score is Map<String, Object?>
        ? _text(score['current'])
        : '';
    final goals = _parseScore(current);
    final status = statusOf(description);

    return ProviderMatch(
      externalId: id.toString(),
      leagueExternalId: league['id'].toString(),
      homeTeamExternalId: home['id'].toString(),
      awayTeamExternalId: away['id'].toString(),
      homeTeamName: _text(home['name']),
      awayTeamName: _text(away['name']),
      kickoffAt: kickoff.toUtc(),
      status: status,
      homeGoals: status == ProviderMatchStatus.finished ? goals?.$1 : null,
      awayGoals: status == ProviderMatchStatus.finished ? goals?.$2 : null,
      currentHomeGoals: status == ProviderMatchStatus.live ? goals?.$1 : null,
      currentAwayGoals: status == ProviderMatchStatus.live ? goals?.$2 : null,
      minute:
          status == ProviderMatchStatus.live && state is Map<String, Object?>
          ? _minute(state['clock'])
          : null,
    );
  }

  /// Maps Highlightly's `state.description`.
  static ProviderMatchStatus statusOf(String description) {
    final text = description.trim().toLowerCase();
    if (text.isEmpty) {
      return ProviderMatchStatus.unknown;
    }
    if (text.startsWith('finished')) {
      return ProviderMatchStatus.finished;
    }
    if (text == 'not started') {
      return ProviderMatchStatus.scheduled;
    }
    if (text.contains('postpon') || text.contains('delay')) {
      return ProviderMatchStatus.postponed;
    }
    if (text.contains('cancel') ||
        text.contains('abandon') ||
        text.contains('suspend') ||
        text.contains('awarded')) {
      return ProviderMatchStatus.cancelled;
    }
    if (text.contains('half') ||
        text.contains('extra time') ||
        text.contains('penalties') ||
        text.contains('break') ||
        text.contains('in progress') ||
        text.contains('live')) {
      return ProviderMatchStatus.live;
    }
    return ProviderMatchStatus.unknown;
  }

  static final RegExp _scorePattern = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$');

  static String _text(Object? raw) => raw is String ? raw : '';

  static int? _minute(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw.replaceAll(RegExp(r"[^0-9]"), ''));
    }
    return null;
  }

  static (int, int)? _parseScore(String raw) {
    final match = _scorePattern.firstMatch(raw);
    if (match == null) {
      return null;
    }
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }
}
