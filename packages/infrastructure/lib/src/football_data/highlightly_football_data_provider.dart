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
///   [providerQuotaErrorCode]. A 429 is treated the same way. The stop
///   holds for [quotaRecheck], then one request is tried again: nothing
///   else tells the adapter that the provider's day has turned. The stop
///   could hold until the server restarted (review of 2026-10-16).
///   The schedule calls keep a reserve; the results calls have an adapter
///   of their own with none, so the reserve is theirs to spend.
/// * **Days:** a day is asked for in Riyadh time (`timezone=Asia/Riyadh`), the
///   day the app's users live in; kickoffs come back as UTC instants.
/// * **Scores:** `state.score.current` (`"2 - 1"`) is the score after extra
///   time; a shoot-out is reported separately and is never part of it.
///
/// Never throws.
final class HighlightlyFootballDataProvider
    implements FootballDataProvider, LeagueStandingsSource {
  /// Creates the adapter.
  HighlightlyFootballDataProvider({
    required String apiKey,
    http.Client? httpClient,
    this.quotaReserve = 25,
    this.standingsReserve = 50,
    this.quotaRecheck = const Duration(hours: 1),
    Uri? baseUri,
    DateTime Function()? clock,
  }) : _apiKey = apiKey,
       _http = httpClient ?? http.Client(),
       _base = baseUri ?? Uri.parse('https://soccer.highlightly.net'),
       _clock = clock ?? DateTime.now;

  final String _apiKey;
  final http.Client _http;
  final Uri _base;

  /// Requests kept in hand before this adapter stops calling.
  final int quotaReserve;

  /// Requests kept in hand before a league table is asked for (script
  /// 189). A table is worth less than a result, so the tables stop well
  /// before the schedule calls do.
  final int standingsReserve;

  /// How long a stop at [quotaReserve] holds before one request is tried.
  final Duration quotaRecheck;

  final DateTime Function() _clock;

  int? _remaining;

  /// When [_remaining] was reported.
  DateTime? _remainingAt;

  /// The provider's last reported remaining daily requests, if any.
  int? get remainingRequests => _remaining;

  static const String _userAgent =
      'Nukhbaa/1.0 (+https://adbrhman.github.io/nukhbaa/)';
  static const Duration _timeout = Duration(seconds: 20);

  /// The table of league [leagueRef] in the season starting [season]
  /// (script 189), from `/standings`: every group's rows, leader first.
  /// Nothing is asked once [standingsReserve] requests or fewer are left.
  @override
  Future<Result<List<LeagueStandingRow>>> standingsOf({
    required String leagueRef,
    required int season,
  }) async {
    final left = _remaining;
    final seenAt = _remainingAt;
    if (left != null &&
        left <= standingsReserve &&
        seenAt != null &&
        _clock().difference(seenAt) < quotaRecheck) {
      return Result.err(
        AppError.transient(
          providerQuotaErrorCode,
          'Keeping the last $left provider requests for results',
        ),
      );
    }

    final uri = _base.replace(
      path: '/standings',
      queryParameters: {'leagueId': leagueRef, 'season': '$season'},
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
      _remainingAt = _clock();
    }
    if (response.statusCode == 429) {
      _remaining = 0;
      _remainingAt = _clock();
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
    final rows = parseStandings(decoded);
    if (rows == null) {
      return const Result.err(
        AppError.transient(
          'football_data.provider_malformed',
          'Highlightly response has no standings groups',
        ),
      );
    }
    return Result.ok(rows);
  }

  /// The rows of a `/standings` response, leader first: `groups` at the
  /// top or under `data`, each with its `standings`. Null when there are no
  /// groups.
  static List<LeagueStandingRow>? parseStandings(Object? decoded) {
    Object? groups;
    if (decoded is Map<String, Object?>) {
      groups = decoded['groups'];
      final data = decoded['data'];
      if (groups == null && data is Map<String, Object?>) {
        groups = data['groups'];
      }
      if (groups == null && data is List<Object?>) {
        groups = data;
      }
    }
    if (groups is! List<Object?>) {
      return null;
    }
    final rows = <LeagueStandingRow>[];
    final seen = <String>{};
    for (final group in groups) {
      if (group is! Map<String, Object?>) {
        continue;
      }
      final standings = group['standings'];
      if (standings is! List<Object?>) {
        continue;
      }
      for (final raw in standings) {
        if (raw is! Map<String, Object?>) {
          continue;
        }
        final team = raw['team'];
        final position = _standingNumber(raw['position']);
        if (team is! Map<String, Object?> ||
            team['id'] == null ||
            position == null) {
          continue;
        }
        final id = team['id'].toString();
        if (!seen.add(id)) {
          continue;
        }
        rows.add(
          LeagueStandingRow(
            teamExternalId: id,
            position: position,
            points: _standingNumber(raw['points']),
            played: _standingNumber(raw['played']),
          ),
        );
      }
    }
    rows.sort((a, b) => a.position.compareTo(b.position));
    return rows;
  }

  static int? _standingNumber(Object? raw) => raw is int
      ? raw
      : raw is num
      ? raw.toInt()
      : raw is String
      ? int.tryParse(raw.trim())
      : null;

  @override
  Future<Result<List<ProviderMatch>>> matchesOn({
    required String leagueExternalId,
    required DateTime riyadhDay,
  }) async {
    final left = _remaining;
    final seenAt = _remainingAt;
    if (left != null &&
        left <= quotaReserve &&
        seenAt != null &&
        _clock().difference(seenAt) < quotaRecheck) {
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
      _remainingAt = _clock();
    }

    if (response.statusCode == 429) {
      _remaining = 0;
      _remainingAt = _clock();
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
