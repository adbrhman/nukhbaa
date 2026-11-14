/// Port for the Elite Cup of the head-to-head league (NK185, migration
/// 0190).
///
/// Backed by `PostgresH2hCupStore`. Every write is append-only and
/// idempotent where it can be (an entry, a result or a title already
/// stored is left as it is); the database keeps the stages in order after
/// the 19 rounds, one stage a day for each path, and a day for one cup day
/// of one month only (0212: paths 2 and 3 share their days).
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The decision of one pair as stored.
final class H2hCupResult {
  /// Creates a result.
  const H2hCupResult({
    required this.slot,
    required this.winner,
    required this.outcome,
    required this.home,
    required this.away,
  });

  /// The pair's slot.
  final int slot;

  /// The winner, or null when both lost.
  final UserId? winner;

  /// How it was decided (`H2hCupOutcome.wire`).
  final String outcome;

  /// The first side's figures.
  final H2hCupSide home;

  /// The second side's figures.
  final H2hCupSide away;
}

/// One stage as stored, with its pairs and, once decided, their results.
final class H2hCupStage {
  /// Creates a stage.
  const H2hCupStage({
    required this.id,
    required this.monthStart,
    required this.step,
    required this.attempt,
    required this.day,
    required this.fixtureCount,
    required this.lockedAt,
    required this.pairs,
    required this.results,
  });

  /// The stage.
  final H2hCupStageId id;

  /// The month whose cup it is.
  final DateTime monthStart;

  /// The path and round.
  final H2hCupStep step;

  /// 1, or more for a stage carried to another day.
  final int attempt;

  /// The Riyadh day of its fixtures, as a UTC midnight.
  final DateTime day;

  /// Fixtures the day held when it was scheduled; once locked, the frozen
  /// count.
  final int fixtureCount;

  /// When its fixtures were frozen, or null.
  final DateTime? lockedAt;

  /// Its pairs, by slot.
  final List<H2hCupPair> pairs;

  /// The results of its pairs, by slot: empty until it is decided.
  final List<H2hCupResult> results;

  /// Whether its fixture list is frozen.
  bool get locked => lockedAt != null;

  /// Whether every pair has a result.
  bool get decided => pairs.isNotEmpty && results.length >= pairs.length;
}

/// A path's title as stored.
final class H2hCupTitle {
  /// Creates a title.
  const H2hCupTitle({
    required this.place,
    required this.champion,
    required this.runnerUp,
    required this.how,
  });

  /// The path.
  final int place;

  /// The champion, or null when vacant.
  final UserId? champion;

  /// The runner-up, or null.
  final UserId? runnerUp;

  /// `final`, `walkover` or `vacant`.
  final String how;
}

/// A month's cup as stored.
final class H2hCupState {
  /// Creates a state.
  const H2hCupState({
    required this.entries,
    required this.stages,
    required this.titles,
  });

  /// Nothing stored yet.
  static const H2hCupState empty = H2hCupState(
    entries: <H2hCupEntry>[],
    stages: <H2hCupStage>[],
    titles: <H2hCupTitle>[],
  );

  /// The qualifiers.
  final List<H2hCupEntry> entries;

  /// Every stage, in day order.
  final List<H2hCupStage> stages;

  /// The titles decided.
  final List<H2hCupTitle> titles;

  /// The qualifiers of [place].
  List<H2hCupEntry> entriesOf(int place) => [
    for (final e in entries)
      if (e.place == place) e,
  ];

  /// The latest attempt of [step], or null.
  H2hCupStage? stageOf(H2hCupStep step) {
    H2hCupStage? found;
    for (final s in stages) {
      if (s.step == step && (found == null || s.attempt > found.attempt)) {
        found = s;
      }
    }
    return found;
  }

  /// The title of [place], or null.
  H2hCupTitle? titleOf(int place) {
    for (final t in titles) {
      if (t.place == place) {
        return t;
      }
    }
    return null;
  }
}

/// What a locked stage's fixtures say now.
final class H2hCupStageFigures {
  /// Creates the figures.
  const H2hCupStageFigures({
    required this.fixtures,
    required this.settled,
    required this.sides,
  });

  /// Fixtures still in play: frozen, on the stage's day, visible, and not
  /// past the result deadline without a result.
  final int fixtures;

  /// Of them, those with a result and no pending score.
  final int settled;

  /// Each player's figures on them; a player with no prediction is absent.
  final Map<UserId, H2hCupSide> sides;

  /// Whether every fixture in play is settled (and there is one).
  bool get judged => fixtures > 0 && settled >= fixtures;

  /// Whether nothing is left to play: the stage is carried.
  bool get empty => fixtures == 0;

  /// The figures of [user].
  H2hCupSide sideOf(UserId user) => sides[user] ?? H2hCupSide.absent;
}

/// The Elite Cup's store.
abstract interface class H2hCupStore {
  /// The cup of [monthStart]: entries, stages with pairs and results, and
  /// titles.
  Future<Result<H2hCupState>> stateOf(DateTime monthStart);

  /// Stores the qualifiers of [monthStart]; entries already stored stay.
  Future<Result<void>> enter(DateTime monthStart, List<H2hCupEntry> entries);

  /// Stores a stage on [day] with its [pairs], in one transaction. A
  /// database refusal (out of order, a day taken, before the 19 rounds) is
  /// an [ErrorKind.invariant] error `h2h.cup_refused`.
  Future<Result<void>> schedule({
    required H2hCupStageId id,
    required DateTime monthStart,
    required H2hCupStep step,
    required int attempt,
    required DateTime day,
    required int fixtureCount,
    required List<H2hCupPair> pairs,
  });

  /// Freezes the fixtures of [stageId]: every visible, non-test fixture of
  /// [day]. Idempotent; returns the frozen count.
  Future<Result<int>> lock({
    required H2hCupStageId stageId,
    required DateTime day,
  });

  /// What the locked stage's fixtures say now.
  Future<Result<H2hCupStageFigures>> figuresOf(H2hCupStageId stageId);

  /// Stores the results of [stageId]'s pairs; results already stored stay.
  Future<Result<void>> decide({
    required H2hCupStageId stageId,
    required List<H2hCupResult> results,
  });

  /// Stores the title of [place]; a title already stored stays.
  Future<Result<void>> crown({
    required DateTime monthStart,
    required int place,
    required UserId? champion,
    required UserId? runnerUp,
    required String how,
  });
}
