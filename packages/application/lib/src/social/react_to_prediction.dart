import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/prediction/list_fixture_predictions.dart';
import 'package:application/src/social/ports/prediction_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: react to another player's prediction (migration 0094).
///
/// Who may react is who may see the prediction: [ListFixturePredictions]
/// lets a member of the season see every prediction for a fixture once it
/// has kicked off, and its refusals pass through unchanged. Then:
/// * an unknown reaction is [ErrorKind.validation]
///   `social.reaction_emoji_unknown` (checked first, before any read);
/// * a participant with no prediction for the fixture is
///   [ErrorKind.invariant] `social.prediction_reaction_no_prediction`;
/// * the caller's own prediction is [ErrorKind.invariant]
///   `social.prediction_reaction_self`.
///
/// One live reaction per player per prediction: reacting again changes it.
/// The owner of the prediction hears of the first reaction each player
/// gives it, in the inbox; a change, or a reaction taken back and given
/// again, tells nobody twice (the notification dedupes on the fixture and
/// the player who reacted). A failed notification never undoes the
/// reaction. Reactions carry no points (decided 2026-10-06).
///
/// Never throws; returns a typed [Result].
final class ReactToPrediction {
  /// Creates the use-case over its collaborators.
  const ReactToPrediction({
    required ListFixturePredictions reveal,
    required CompetitionRepository competition,
    required PredictionReactionRepository reactions,
    required CreateNotification notify,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _reveal = reveal,
       _competition = competition,
       _reactions = reactions,
       _notify = notify,
       _idGenerator = idGenerator,
       _clock = clock;

  final ListFixturePredictions _reveal;
  final CompetitionRepository _competition;
  final PredictionReactionRepository _reactions;
  final CreateNotification _notify;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// [principal] reacts with [emoji] to [targetParticipantId]'s prediction
  /// for [fixtureId] in [seasonId].
  Future<Result<PredictionReactionWrite>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
    required String targetParticipantId,
    required String emoji,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final emojiResult = ReactionEmoji.tryParse(emoji);
    if (emojiResult is Err<ReactionEmoji>) {
      return Result.err(emojiResult.error);
    }
    final targetResult = ParticipantId.tryParse(targetParticipantId);
    if (targetResult is Err<ParticipantId>) {
      return Result.err(targetResult.error);
    }
    final ParticipantId target = (targetResult as Ok<ParticipantId>).value;

    final gate = await _reveal(
      principal: principal,
      seasonId: seasonId,
      fixtureId: fixtureId,
    );
    if (gate is Err<FixturePredictionReveal>) {
      return Result.err(gate.error);
    }
    final FixturePredictionReveal reveal =
        (gate as Ok<FixturePredictionReveal>).value;
    // The reveal parsed both ids before it let the caller through.
    final SeasonId season = (SeasonId.tryParse(seasonId) as Ok<SeasonId>).value;
    final FixtureRef fixture =
        (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value;

    final bool predicted = reveal.predictions.any(
      (view) => view.prediction.participantId == target,
    );
    if (!predicted) {
      return const Result.err(
        AppError.invariant(
          'social.prediction_reaction_no_prediction',
          'That player has no prediction for this fixture',
        ),
      );
    }

    final meResult = await _competition.findParticipant(
      season,
      principal.userId,
    );
    if (meResult is Err<Participant?>) {
      return Result.err(meResult.error);
    }
    if ((meResult as Ok<Participant?>).value?.id == target) {
      return const Result.err(
        AppError.invariant(
          'social.prediction_reaction_self',
          'Nobody reacts to their own prediction',
        ),
      );
    }

    final written = await _reactions.upsert(
      id: _idGenerator.newUuid(),
      seasonId: season,
      fixture: fixture,
      target: target,
      reactor: principal.userId,
      kind: (emojiResult as Ok<ReactionEmoji>).value.kind,
      reactedAt: _clock.nowUtc(),
    );
    if (written is Err<PredictionReactionWrite>) {
      return Result.err(written.error);
    }
    final PredictionReactionWrite write =
        (written as Ok<PredictionReactionWrite>).value;
    if (write.inserted) {
      await _notify(
        recipientId: write.targetUserId,
        kind: NotificationKind.predictionReaction,
        subject: NotificationSubject.predictionReaction(
          fixture: fixture,
          actorUserId: principal.userId,
        ),
      );
    }
    return Result.ok(write);
  }
}
