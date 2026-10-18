import 'package:application/src/football_data/ports/live_score_board.dart';
import 'package:application/src/football_data/ports/live_score_corrections.dart';

/// The [LiveScoreBoard] players read: the provider's running scores as
/// [raw] holds them, with the admins' [LiveScoreCorrections] laid over them
/// ([LiveScoreCorrection.applyTo]). The fixtures feed and the live standing
/// (`GetLiveStanding`) both read through it, so a corrected score shows and
/// grades the same everywhere. Writes go to [raw] untouched: the provider
/// poll keeps writing what the provider says.
///
/// A correction shows only while the provider reports the match: with no
/// running score on [raw] there is nothing to correct.
final class CorrectedLiveScoreBoard implements LiveScoreBoard {
  /// Creates the board over [raw] and [corrections].
  const CorrectedLiveScoreBoard({
    required LiveScoreBoard raw,
    required LiveScoreCorrections corrections,
  }) : _raw = raw,
       _corrections = corrections;

  final LiveScoreBoard _raw;
  final LiveScoreCorrections _corrections;

  @override
  void put(Map<String, LiveScore> scores) => _raw.put(scores);

  @override
  void remove(Iterable<String> fixtureIds) => _raw.remove(fixtureIds);

  @override
  Map<String, LiveScore> read(Iterable<String> fixtureIds) {
    final scores = _raw.read(fixtureIds);
    return <String, LiveScore>{
      for (final entry in scores.entries)
        entry.key: _corrected(entry.key, entry.value),
    };
  }

  LiveScore _corrected(String fixtureId, LiveScore score) {
    final correction = _corrections.of(fixtureId);
    if (correction == null) {
      return score;
    }
    final counted = correction.applyTo(score.homeGoals, score.awayGoals);
    return LiveScore(
      homeGoals: counted.homeGoals,
      awayGoals: counted.awayGoals,
      minute: score.minute,
      finished: score.finished,
      updatedAt: score.updatedAt,
    );
  }
}
