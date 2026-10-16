import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:application/src/notification/ports/score_announcement_repository.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Tier-3 side effect of an admin hiding fixtures (script 89): everyone who
/// made a hidden fixture their day's double is told that the double is free
/// again.
///
/// A hidden fixture is never scored, and since migration 0172 its double no
/// longer counts towards the one double a Riyadh day allows, so the player
/// may mark another match of that day that has not kicked off. A match is
/// usually hidden because it was postponed or called off, and a player who
/// does not hear of it loses the double for nothing.
///
/// * Only a double on a fixture whose Riyadh day has not ended is
///   announced: an older day has nothing left to move it to. A test fixture
///   is never announced.
/// * **Once per player and fixture:** [CreateNotification] dedupes on
///   `(recipient, double_released, fixture)`, and only a new inbox row rings
///   the phone, so hiding the fixture again after showing it says nothing.
/// * Players are reached the way the exact-hit announcement reaches them
///   ([ScoreAnnouncementRepository.targetsForParticipants]): a player with
///   no registered device is not a target. Inside the quiet hours
///   ([QuietHours]) the inbox row is written and the push is left out: by
///   the morning the day is over.
///
/// Best effort: a failure skips that fixture or player and never fails the
/// hiding. Returns the number of players told.
final class NotifyDoubleReleased {
  /// Creates the use-case over its collaborators.
  const NotifyDoubleReleased({
    required FixtureScheduleRepository schedules,
    required FixturePredictionRepository predictions,
    required ScoreAnnouncementRepository targets,
    required PushSender sender,
    required CreateNotification create,
    required Clock clock,
  }) : _schedules = schedules,
       _predictions = predictions,
       _targets = targets,
       _sender = sender,
       _create = create,
       _clock = clock;

  final FixtureScheduleRepository _schedules;
  final FixturePredictionRepository _predictions;
  final ScoreAnnouncementRepository _targets;
  final PushSender _sender;
  final CreateNotification _create;
  final Clock _clock;

  /// The push title.
  static const String title = 'تحرّرت مضاعفتك ⚡';

  /// The push body for the match `home - away` named [game].
  static String body(String game) =>
      'أُوقفت مباراة «$game» فلن تُحتسب. ضع مضاعفتك على مباراة أخرى من '
      'مباريات يومها لم تنطلق بعد.';

  /// Tells the players who doubled any of the just-hidden [fixtures].
  Future<Result<int>> call({required List<FixtureRef> fixtures}) async {
    final DateTime now = _clock.nowUtc();
    final DateTime today = riyadhDayOf(now);
    var told = 0;
    for (final fixture in fixtures) {
      final scheduleResult = await _schedules.findByFixture(fixture);
      if (scheduleResult is Err<FixtureSchedule?>) {
        continue;
      }
      final FixtureSchedule? schedule =
          (scheduleResult as Ok<FixtureSchedule?>).value;
      if (schedule == null ||
          schedule.isTest ||
          riyadhDayOf(schedule.kickoffAt).isBefore(today)) {
        continue;
      }

      final listed = await _predictions.listByFixture(fixture);
      if (listed is Err<List<FixturePredictionView>>) {
        continue;
      }
      final doubled = <ParticipantId>[
        for (final view in (listed as Ok<List<FixturePredictionView>>).value)
          if (view.prediction.isDouble) view.prediction.participantId,
      ];
      if (doubled.isEmpty) {
        continue;
      }

      final targetsResult = await _targets.targetsForParticipants(doubled);
      if (targetsResult is Err<List<ScoreNoticeTarget>>) {
        continue;
      }
      final tokens = <String>[];
      for (final target
          in (targetsResult as Ok<List<ScoreNoticeTarget>>).value) {
        final created = await _create(
          recipientId: target.userId,
          kind: NotificationKind.doubleReleased,
          subject: NotificationSubject.doubleReleased(fixture: fixture),
        );
        // Already told, or the row could not be written: no push either.
        if (created is! Ok<bool> || !created.value) {
          continue;
        }
        told++;
        if (!QuietHours.covers(
          now,
          utcOffsetMinutes: target.utcOffsetMinutes,
        )) {
          tokens.addAll(target.tokens);
        }
      }
      if (tokens.isNotEmpty) {
        await _sender.send(
          tokens: tokens,
          title: title,
          body: body('${schedule.homeTeam} - ${schedule.awayTeam}'),
          link: PushLink.fixtures,
        );
      }
    }
    return Result.ok(told);
  }
}
