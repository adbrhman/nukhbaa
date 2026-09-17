import 'package:application/application.dart';

/// [LiveScoreBoard] kept in the server process. A score not refreshed for
/// [staleAfter] is forgotten, so a stalled poll never leaves a stale score on
/// screen. One server instance, so no sharing is needed; a restart simply
/// starts empty and fills again on the next poll.
final class InMemoryLiveScoreBoard implements LiveScoreBoard {
  /// Creates an empty board; [now] is injectable for tests.
  InMemoryLiveScoreBoard({
    this.staleAfter = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long a score survives without a refresh.
  final Duration staleAfter;

  final DateTime Function() _now;
  final Map<String, LiveScore> _scores = <String, LiveScore>{};

  @override
  void put(Map<String, LiveScore> scores) => _scores.addAll(scores);

  @override
  void remove(Iterable<String> fixtureIds) {
    for (final id in fixtureIds) {
      _scores.remove(id);
    }
  }

  @override
  Map<String, LiveScore> read(Iterable<String> fixtureIds) {
    final cutoff = _now().toUtc().subtract(staleAfter);
    _scores.removeWhere((_, score) => score.updatedAt.isBefore(cutoff));
    return <String, LiveScore>{
      for (final id in fixtureIds)
        if (_scores[id] != null) id: _scores[id]!,
    };
  }
}
