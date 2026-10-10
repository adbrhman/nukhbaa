/// Where each head-to-head round stands for the screen (migration 0100):
/// the server's round state, with the round that takes predictions now told
/// apart from the ones after it.
library;

import 'package:application/src/gamification/get_my_h2h_league.dart';
import 'package:domain/domain.dart';

/// A round's phase as the caller's screen shows it.
enum H2hRoundPhase {
  /// The first round whose fixture list is not frozen yet: the next one to
  /// be played, taking predictions now.
  open,

  /// An approved round after the open one.
  upcoming,

  /// Started, not every result is in.
  live,

  /// Every result is in.
  settled,

  /// No fixture of the round is left: it counts for nobody.
  voided,
}

/// The phase of every round in [rounds], keyed by round number.
///
/// It reads the server's state only (`H2hRoundStatus`, from the frozen
/// lists and the stored results), never the calendar: of the rounds not
/// started, the lowest number is [H2hRoundPhase.open] and the rest are
/// [H2hRoundPhase.upcoming].
Map<int, H2hRoundPhase> h2hRoundPhasesOf(List<MyH2hRound> rounds) {
  final ordered = List<MyH2hRound>.of(rounds)
    ..sort((a, b) => a.round.number.compareTo(b.round.number));
  final phases = <int, H2hRoundPhase>{};
  var openTaken = false;
  for (final view in ordered) {
    final H2hRoundPhase phase;
    switch (view.status) {
      case H2hRoundStatus.upcoming:
        phase = openTaken ? H2hRoundPhase.upcoming : H2hRoundPhase.open;
        openTaken = true;
      case H2hRoundStatus.live:
        phase = H2hRoundPhase.live;
      case H2hRoundStatus.settled:
        phase = H2hRoundPhase.settled;
      case H2hRoundStatus.voided:
        phase = H2hRoundPhase.voided;
    }
    phases[view.round.number] = phase;
  }
  return phases;
}

/// The result the screen shows for [view], or null when it shows none.
///
/// A settled round shows the policy's result, the one the table counts. A
/// live round shows where the points stand so far and nothing else: the
/// policy's live result also weighs whether the opponent predicted at all,
/// which would tell the caller about the opponent's picks on fixtures that
/// have not kicked off. The points themselves are stored scores, which exist
/// only for fixtures already played. It is a display, not a score: nothing
/// stores or ranks it.
H2hMatchResult? h2hShownResultOf(MyH2hRound view) {
  final match = view.match;
  if (match == null) {
    return null;
  }
  switch (view.status) {
    case H2hRoundStatus.settled:
      return match.result;
    case H2hRoundStatus.live:
      if (!match.present) {
        return H2hMatchResult.loss;
      }
      final mine = match.points.toDouble();
      if (mine > match.opponentPoints) {
        return H2hMatchResult.win;
      }
      if (mine < match.opponentPoints) {
        return H2hMatchResult.loss;
      }
      return H2hMatchResult.draw;
    case H2hRoundStatus.upcoming:
    case H2hRoundStatus.voided:
      return null;
  }
}
