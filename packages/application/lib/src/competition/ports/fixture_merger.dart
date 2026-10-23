import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// What merging a copy of a match into the copy kept did, or would do
/// (`competition.merge_fixture_copies`, migration 0176, script 95).
final class FixtureMergeReport {
  /// Creates the report.
  const FixtureMergeReport({
    required this.moved,
    required this.doublesMoved,
    required this.doublesDropped,
    required this.bothPredicted,
    required this.late,
    required this.notParticipant,
    required this.linkMoved,
    required this.keptHasResult,
    this.applied = false,
    this.rescored = false,
  });

  /// Predictions moved to the kept copy.
  final int moved;

  /// Of [moved], those that kept their double.
  final int doublesMoved;

  /// Of [moved], those that lost their double: the player already had the
  /// one double of the kept copy's Riyadh day on another match.
  final int doublesDropped;

  /// Players who predicted both copies: their prediction of the kept copy
  /// stands, the other stays on the copy.
  final int bothPredicted;

  /// Predictions sent at or after the kept copy's kickoff: they stay.
  final int late;

  /// Players not in a season of the kept copy: their prediction stays.
  final int notParticipant;

  /// Whether the copy's provider link went to the kept copy.
  final bool linkMoved;

  /// Whether the kept copy has a recorded result.
  final bool keptHasResult;

  /// Whether this is what was done (`true`) or a preview (`false`).
  final bool applied;

  /// Whether the kept copy was scored and posted again after the merge.
  final bool rescored;

  /// This report as applied, with [rescored].
  FixtureMergeReport appliedWith({required bool rescored}) =>
      FixtureMergeReport(
        moved: moved,
        doublesMoved: doublesMoved,
        doublesDropped: doublesDropped,
        bothPredicted: bothPredicted,
        late: late,
        notParticipant: notParticipant,
        linkMoved: linkMoved,
        keptHasResult: keptHasResult,
        applied: true,
        rescored: rescored,
      );
}

/// A fixture and the other copies of its match: the visible or hidden,
/// non-test fixtures less than 12 hours from it with one of its clubs (the
/// same catalog team or the same name key, migrations 0110 and 0175), and
/// the same match put back up to 7 days later: the same two catalog teams,
/// in one of its seasons (migration 0182).
final class FixtureCopy {
  /// Creates one row.
  const FixtureCopy({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.hidden,
    required this.predictions,
    required this.doubles,
    required this.hasResult,
    required this.linked,
    required this.isSelf,
  });

  /// The fixture.
  final FixtureRef fixture;

  /// Its home side as stored.
  final String homeTeam;

  /// Its away side as stored.
  final String awayTeam;

  /// Its kickoff.
  final DateTime kickoffAt;

  /// Whether it is hidden from the players.
  final bool hidden;

  /// How many predictions it holds.
  final int predictions;

  /// How many of them are doubled.
  final int doubles;

  /// Whether its result is recorded.
  final bool hasResult;

  /// Whether a provider match is linked to it.
  final bool linked;

  /// Whether this row is the fixture asked about.
  final bool isSelf;
}

/// Merges a copy of a match into the copy kept, and finds the copies of a
/// match (migration 0176).
abstract interface class FixtureMerger {
  /// Merges [duplicate] into [kept] on behalf of [actor] when [apply] is
  /// true, in one transaction: the predictions that may move, the copy
  /// hidden for good, its provider link, the audit row. With [apply] false
  /// nothing is written. A refusal is an Arabic [AppError].
  Future<Result<FixtureMergeReport>> merge({
    required FixtureRef duplicate,
    required FixtureRef kept,
    required UserId actor,
    required bool apply,
  });

  /// [fixture] first, then the other copies of its match not merged yet,
  /// by kickoff. Empty when [fixture] has no schedule.
  Future<Result<List<FixtureCopy>>> copiesOf(FixtureRef fixture);
}
