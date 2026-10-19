import 'dart:async';
import 'dart:convert';

import 'package:application/application.dart';
import 'package:http/http.dart' as http;
import 'package:infrastructure/src/football_data/highlightly_football_data_provider.dart';
import 'package:shared/shared.dart';

/// [MatchDetailsSource] over Highlightly's `GET /matches/{id}` (direct
/// plan), whose `events` list carries every goal, card, substitution and VAR
/// decision with its minute: the probe of 2026-10-19 (script 117) read Paris
/// FC 4-3 Rennes FC with 26 of them on the free plan.
///
/// * **Quota:** one request per finished match. Details are the last thing
///   the shared daily quota is spent on: once the provider reports
///   [quotaReserve] requests left, this source stops for [quotaRecheck] and
///   returns [providerQuotaErrorCode].
/// * **Kinds:** the provider's event names are mapped to [MatchEventKind]
///   ([kindOf]); a name not known here is kept as [MatchEventKind.other]
///   with the name in [MatchEvent.detail].
/// * **Half time:** worked out from the goals
///   ([MatchDetails.halfTimeFromEvents]).
///
/// Never throws.
final class HighlightlyMatchDetailsSource implements MatchDetailsSource {
  /// Creates the source.
  HighlightlyMatchDetailsSource({
    required String apiKey,
    http.Client? httpClient,
    this.quotaReserve = 40,
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
  final DateTime Function() _clock;

  /// Requests kept in hand for the schedules and results.
  final int quotaReserve;

  /// How long a stop at [quotaReserve] holds before one request is tried.
  final Duration quotaRecheck;

  int? _remaining;
  DateTime? _remainingAt;

  static const String _userAgent =
      'Nukhbaa/1.0 (+https://adbrhman.github.io/nukhbaa/)';
  static const Duration _timeout = Duration(seconds: 20);

  @override
  String get source => 'highlightly';

  @override
  Future<Result<MatchDetails?>> details({
    required String externalMatchId,
    required String fixtureId,
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
          'Keeping the last $left provider requests for schedules and '
          'results',
        ),
      );
    }

    final uri = _base.replace(
      path: '/matches/${Uri.encodeComponent(externalMatchId)}',
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
    // The match comes alone or as a one-item list.
    final Object? match = decoded is List<Object?> && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    if (match is! Map<String, Object?>) {
      return const Result.err(
        AppError.transient(
          'football_data.provider_malformed',
          'Highlightly match response is not an object',
        ),
      );
    }
    return Result.ok(
      parseDetails(
        match,
        fixtureId: fixtureId,
        source: source,
        fetchedAt: _clock().toUtc(),
      ),
    );
  }

  /// Maps one Highlightly match object; null while the match is not over.
  static MatchDetails? parseDetails(
    Map<String, Object?> json, {
    required String fixtureId,
    required String source,
    required DateTime fetchedAt,
  }) {
    final state = json['state'];
    final description = state is Map<String, Object?>
        ? (state['description'] is String
              ? state['description']! as String
              : '')
        : '';
    if (HighlightlyFootballDataProvider.statusOf(description) !=
        ProviderMatchStatus.finished) {
      return null;
    }
    final homeId = _idOf(json['homeTeam']);
    final awayId = _idOf(json['awayTeam']);
    final events = <MatchEvent>[];
    final rawEvents = json['events'];
    if (rawEvents is List<Object?>) {
      for (final raw in rawEvents) {
        if (raw is! Map<String, Object?>) {
          continue;
        }
        final teamId = _idOf(raw['team']);
        if (teamId == null || (teamId != homeId && teamId != awayId)) {
          continue;
        }
        final type = _text(raw['type']) ?? '';
        events.add(
          MatchEvent(
            minute: _text(raw['time']) ?? '',
            kind: kindOf(type),
            home: teamId == homeId,
            player: _text(raw['player']),
            assist: _text(raw['assist']) ?? _text(raw['substituted']),
            detail: type.isEmpty ? null : type,
          ),
        );
      }
    }
    final halfTime = MatchDetails.halfTimeFromEvents(events);
    final venue = json['venue'];
    final referee = json['referee'];
    return MatchDetails(
      fixtureId: fixtureId,
      found: true,
      source: source,
      externalMatchId: json['id']?.toString(),
      events: events,
      halfTimeHome: halfTime?.$1,
      halfTimeAway: halfTime?.$2,
      venue: venue is Map<String, Object?> ? _text(venue['name']) : null,
      round: _text(json['round']),
      referee: referee is Map<String, Object?>
          ? _text(referee['name'])
          : _text(referee),
      fetchedAt: fetchedAt,
    );
  }

  /// The app's kind for one of Highlightly's event names.
  static MatchEventKind kindOf(String type) {
    final text = type.trim().toLowerCase();
    if (text.contains('cancel') || text.contains('disallow')) {
      return text.contains('goal')
          ? MatchEventKind.varGoalCancelled
          : MatchEventKind.other;
    }
    if (text.startsWith('var')) {
      return MatchEventKind.other;
    }
    if (text.contains('own goal')) {
      return MatchEventKind.ownGoal;
    }
    if (text.contains('missed') && text.contains('penalty')) {
      return MatchEventKind.missedPenalty;
    }
    if (text == 'penalty' || text == 'penalty goal') {
      return MatchEventKind.penaltyGoal;
    }
    if (text == 'goal') {
      return MatchEventKind.goal;
    }
    if (text.contains('second yellow') || text.contains('yellow-red')) {
      return MatchEventKind.secondYellow;
    }
    if (text.contains('yellow')) {
      return MatchEventKind.yellowCard;
    }
    if (text.contains('red card')) {
      return MatchEventKind.redCard;
    }
    if (text.contains('substitution')) {
      return MatchEventKind.substitution;
    }
    return MatchEventKind.other;
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
