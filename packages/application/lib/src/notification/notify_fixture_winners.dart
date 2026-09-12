import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:application/src/notification/ports/score_announcement_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Tier-3 side effect of scoring: tell everyone who called a fixture EXACTLY
/// that they did, the moment the fixture is scored.
///
/// **Exactly once per user per fixture.** The guard is not a timer and not a
/// flag on the score: it is [CreateNotification], whose
/// `createIfAbsent` is keyed on `(recipient, kind, subjectRef)` where the
/// subject is the fixture itself. A re-score -- an admin correcting a result,
/// a replay, a retry -- therefore finds the row already there, answers
/// `Ok(false)`, and sends NO second push. A user who was NOT a winner before
/// the correction and IS one after still gets theirs, because their own row
/// does not exist yet.
///
/// **Best effort by construction.** Every failure below returns a
/// [Result.err] that the caller ([ScoreFixture]) drops on the floor: points
/// are Tier-1 and must never fail because a phone was unreachable.
///
/// Returns the number of users actually pushed to.
final class NotifyFixtureWinners {
  /// Creates the use-case over its collaborators.
  const NotifyFixtureWinners({
    required ScoreAnnouncementRepository announcements,
    required PushSender sender,
    required CreateNotification create,
  }) : _announcements = announcements,
       _sender = sender,
       _create = create;

  final ScoreAnnouncementRepository _announcements;
  final PushSender _sender;
  final CreateNotification _create;

  /// The title of an ordinary exact hit.
  static const String exactTitle = 'توقع مطابق 🎯';

  /// The title when the hit was the day's double.
  static const String doubleTitle = 'دبل مطابق ⚡';

  /// Announces every exact call among [scores] for [fixture].
  Future<Result<int>> call({
    required FixtureRef fixture,
    required List<ParticipantFixtureScore> scores,
  }) async {
    final winners = <ParticipantId, ParticipantFixtureScore>{};
    for (final score in scores) {
      if (score.result.grade == FixtureScoreGrade.exactScoreline &&
          score.points > 0) {
        winners[score.participantId] = score;
      }
    }
    if (winners.isEmpty) {
      return const Result.ok(0);
    }

    final targetsResult = await _announcements.targetsForParticipants(
      winners.keys.toList(),
    );
    if (targetsResult is Err<List<ScoreNoticeTarget>>) {
      return Result.err(targetsResult.error);
    }
    final targets = (targetsResult as Ok<List<ScoreNoticeTarget>>).value;
    if (targets.isEmpty) {
      return const Result.ok(0);
    }

    // The label is decoration: a fixture with no schedule row still earns its
    // owner a notification, just a shorter one.
    final labelResult = await _announcements.matchLabel(fixture);
    final String? label = labelResult is Ok<String?> ? labelResult.value : null;

    var pushed = 0;
    for (final target in targets) {
      final score = winners[target.participantId];
      if (score == null) {
        continue;
      }

      final created = await _create(
        recipientId: target.userId,
        kind: NotificationKind.fixtureScored,
        subject: NotificationSubject.fixtureScored(fixture: fixture),
      );
      if (created is Err<bool>) {
        continue;
      }
      // Already announced: the push went out the first time this fixture was
      // scored, and a correction must not ring the same phone again.
      if (!(created as Ok<bool>).value) {
        continue;
      }

      final sent = await _sender.send(
        tokens: target.tokens,
        title: score.points >= _doubleFrom ? doubleTitle : exactTitle,
        body: _body(points: score.points, label: label),
      );
      if (sent is Ok<List<String>>) {
        pushed++;
      }
    }

    return Result.ok(pushed);
  }

  /// Points at or above which the hit can only have been doubled: the exact
  /// award is 3, its double 6 (docs/project-context.md, scoring rules).
  static const int _doubleFrom = 6;

  static String _body({required int points, required String? label}) {
    final String head = points >= _doubleFrom
        ? 'ضاعفت نقاطك وأصبت النتيجة بالضبط'
        : 'أصبت النتيجة بالضبط';
    final String where = label == null ? '' : ' في $label';
    return '$head$where — +$points نقاط ✅';
  }
}
