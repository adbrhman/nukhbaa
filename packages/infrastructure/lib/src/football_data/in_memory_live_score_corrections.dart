import 'package:application/application.dart';

/// [LiveScoreCorrections] kept in the server process, beside the
/// [InMemoryLiveScoreBoard] they correct. One server instance, so no sharing
/// is needed. A correction older than [keepFor] is forgotten: by then the
/// match's result is long recorded (the result sync stops asking 24 hours
/// after kickoff). A restart forgets every correction, as it forgets the
/// running scores; a correction made during a match a restart interrupts is
/// made again from the admin panel.
final class InMemoryLiveScoreCorrections implements LiveScoreCorrections {
  /// Creates an empty store; [now] is injectable for tests.
  InMemoryLiveScoreCorrections({
    this.keepFor = const Duration(hours: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long a correction is kept.
  final Duration keepFor;

  final DateTime Function() _now;
  final Map<String, LiveScoreCorrection> _corrections =
      <String, LiveScoreCorrection>{};

  @override
  void set(String fixtureId, LiveScoreCorrection correction) {
    _forgetOld();
    _corrections[fixtureId] = correction;
  }

  @override
  void clear(String fixtureId) => _corrections.remove(fixtureId);

  @override
  LiveScoreCorrection? of(String fixtureId) {
    _forgetOld();
    return _corrections[fixtureId];
  }

  void _forgetOld() {
    final cutoff = _now().toUtc().subtract(keepFor);
    _corrections.removeWhere(
      (_, correction) => correction.setAt.isBefore(cutoff),
    );
  }
}
