import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The reactions one prediction received, as the viewer sees them.
final class PredictionReactionTally {
  /// Creates the tally of [targetParticipantId]'s prediction.
  const PredictionReactionTally({
    required this.targetParticipantId,
    required this.counts,
    this.mine,
  });

  /// The participant whose prediction it is.
  final ParticipantId targetParticipantId;

  /// How many players gave each kind; a kind nobody gave is absent.
  final Map<ReactionKind, int> counts;

  /// The kind the viewer gave, or null.
  final ReactionKind? mine;

  /// Every reaction the prediction received.
  int get total => counts.values.fold(0, (int a, int b) => a + b);
}

/// What storing a reaction did.
final class PredictionReactionWrite {
  /// Creates the outcome of a store.
  const PredictionReactionWrite({
    required this.inserted,
    required this.targetUserId,
  });

  /// True for the reactor's first reaction to this prediction; false when
  /// an earlier one was changed.
  final bool inserted;

  /// The player whose prediction it is.
  final UserId targetUserId;
}

/// Persistence port over `social.prediction_reactions` (migration 0094).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. Every rule is checked by the use-case
/// before a write; the table's trigger is only the backstop.
abstract interface class PredictionReactionRepository {
  /// Stores [reactor]'s [kind] on [target]'s prediction for [fixture] in
  /// [seasonId], replacing any earlier reaction of theirs to it. [id] is
  /// used only when the reaction is new.
  Future<Result<PredictionReactionWrite>> upsert({
    required String id,
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
    required ReactionKind kind,
    required DateTime reactedAt,
  });

  /// Takes back [reactor]'s reaction to [target]'s prediction for
  /// [fixture]; `Ok(false)` when there was none.
  Future<Result<bool>> remove({
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
  });

  /// The reactions every prediction for [fixture] in [seasonId] received,
  /// one tally per prediction that has any, with what [viewer] gave.
  Future<Result<List<PredictionReactionTally>>> tallies({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required UserId viewer,
  });
}
