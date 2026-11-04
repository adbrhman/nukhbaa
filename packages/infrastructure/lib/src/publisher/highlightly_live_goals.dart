import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:infrastructure/src/football_data/highlightly_match_details_source.dart';
import 'package:shared/shared.dart';

/// [LiveGoalDetails] over Highlightly (direct plan): who scored, and when,
/// while the match is still in play.
///
/// The fixture's Highlightly match is found once in its league's list of
/// the day (one request per league and day, kept 30 minutes), as
/// `SyncMatchDetails` finds it: the one match kicking off within ten
/// minutes of it. Then each question is one `GET /matches/{id}`. It stops
/// with [quotaReserve] requests left of the day, above what the schedules,
/// the results and the match details keep for themselves, so the publisher
/// never takes their share.
final class HighlightlyLiveGoals implements LiveGoalDetails {
  /// Creates the source.
  HighlightlyLiveGoals({
    required String apiKey,
    required Map<String, String> leagueIds,
    required FootballDataProvider lister,
    http.Client? httpClient,
    DateTime Function()? clock,
    Uri? baseUri,
    this.quotaReserve = 55,
  }) : _apiKey = apiKey,
       _leagueIds = leagueIds,
       _lister = lister,
       _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _base = baseUri ?? Uri.parse('https://soccer.highlightly.net');

  final String _apiKey;
  final Map<String, String> _leagueIds;
  final FootballDataProvider _lister;
  final http.Client _http;
  final DateTime Function() _clock;
  final Uri _base;

  /// Requests of the day kept for the other jobs.
  final int quotaReserve;

  final Map<String, String> _matchIds = <String, String>{};
  final Map<String, ({List<ProviderMatch> list, DateTime at})> _lists =
      <String, ({List<ProviderMatch> list, DateTime at})>{};
  int? _remaining;
  DateTime? _remainingAt;

  static const Duration _listFor = Duration(minutes: 30);
  static const Duration _kickoffTolerance = Duration(minutes: 10);
  static const Duration _timeout = Duration(seconds: 20);

  @override
  Future<Result<List<MatchEvent>?>> eventsOf({
    required String fixtureId,
    required String leagueName,
    required DateTime kickoffAt,
  }) async {
    if (_holding) {
      return const Result.ok(null);
    }
    var matchId = _matchIds[fixtureId];
    if (matchId == null) {
      final leagueId = _leagueIds[leagueName.trim()];
      if (leagueId == null) {
        return const Result.ok(null);
      }
      final day = riyadhDayOf(kickoffAt);
      final key = '$leagueId|${isoDay(day)}';
      final now = _clock();
      var cached = _lists[key];
      if (cached == null || now.difference(cached.at) > _listFor) {
        final fetched = await _lister.matchesOn(
          leagueExternalId: leagueId,
          riyadhDay: day,
        );
        if (fetched is Err<List<ProviderMatch>>) {
          return Result.err(fetched.error);
        }
        cached = (list: (fetched as Ok<List<ProviderMatch>>).value, at: now);
        _lists[key] = cached;
      }
      final near = <ProviderMatch>[
        for (final match in cached.list)
          if (match.kickoffAt.toUtc().difference(kickoffAt.toUtc()).abs() <=
              _kickoffTolerance)
            match,
      ];
      if (near.length != 1) {
        return const Result.ok(null);
      }
      matchId = near.single.externalId;
      _matchIds[fixtureId] = matchId;
    }
    return _events(matchId);
  }

  bool get _holding {
    final left = _remaining;
    final at = _remainingAt;
    return left != null &&
        left <= quotaReserve &&
        at != null &&
        _clock().difference(at) < const Duration(hours: 1);
  }

  Future<Result<List<MatchEvent>?>> _events(String matchId) async {
    final http.Response response;
    try {
      response = await _http
          .get(
            _base.replace(path: '/matches/${Uri.encodeComponent(matchId)}'),
            headers: <String, String>{
              'x-rapidapi-key': _apiKey,
              'User-Agent':
                  'Nukhbaa/1.0 (+https://adbrhman.github.io/nukhbaa/)',
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
      return const Result.ok(null);
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
    final Object? match = decoded is List<Object?> && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    if (match is! Map<String, Object?>) {
      return const Result.ok(null);
    }
    return Result.ok(parseEvents(match));
  }

  /// The events of one Highlightly match object, whatever its state, in the
  /// app's kinds ([HighlightlyMatchDetailsSource.kindOf]).
  static List<MatchEvent> parseEvents(Map<String, Object?> json) {
    final homeId = _idOf(json['homeTeam']);
    final awayId = _idOf(json['awayTeam']);
    final events = <MatchEvent>[];
    final raw = json['events'];
    if (raw is! List<Object?>) {
      return events;
    }
    for (final item in raw) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final teamId = _idOf(item['team']);
      if (teamId == null || (teamId != homeId && teamId != awayId)) {
        continue;
      }
      final type = _text(item['type']) ?? '';
      events.add(
        MatchEvent(
          minute: _text(item['time']) ?? '',
          kind: HighlightlyMatchDetailsSource.kindOf(type),
          home: teamId == homeId,
          player: _text(item['player']),
          assist: _text(item['assist']),
          detail: type.isEmpty ? null : type,
        ),
      );
    }
    return events;
  }

  static String? _idOf(Object? team) =>
      team is Map<String, Object?> ? team['id']?.toString() : null;

  static String? _text(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (raw is num) {
      return raw.toString();
    }
    return null;
  }
}
