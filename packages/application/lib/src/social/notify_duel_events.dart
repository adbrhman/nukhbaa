import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/notification_queue.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:application/src/social/ports/duel_notice_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Tier-3 side effects of duels (migration 0092): tell a privately
/// challenged player, and tell a challenger when someone accepts.
///
/// **Once per event.** [CreateNotification] keys the in-app row on the
/// challenge (and, for an acceptance, the player who accepted), so a retry
/// never rings the same phone twice.
///
/// **Best effort.** The caller ignores the result: a challenge or a duel
/// exists whether or not a phone was reachable.
///
/// **Quiet hours.** Like the exact-hit push, a push that would arrive
/// between 23:00 and 08:00 on the recipient's clock is queued for 08:00;
/// the in-app notification is written at once. These pushes answer another
/// player's action, so they are not counted in the weekly reminder budget.
final class NotifyDuelEvents {
  /// Creates the use-case over its collaborators.
  const NotifyDuelEvents({
    required DuelNoticeReader notices,
    required CreateNotification create,
    required PushSender sender,
    required NotificationQueue queue,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _notices = notices,
       _create = create,
       _sender = sender,
       _queue = queue,
       _idGenerator = idGenerator,
       _clock = clock;

  final DuelNoticeReader _notices;
  final CreateNotification _create;
  final PushSender _sender;
  final NotificationQueue _queue;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Push title for a private challenge.
  static const String challengedTitle = 'تحدٍّ جديد ⚔️';

  /// Push title for an accepted challenge.
  static const String acceptedTitle = 'قُبل تحديك ⚔️';

  /// Tells the private target of [challenge]. `Ok(true)` when a new
  /// notification was written; `Ok(false)` for an open challenge or a
  /// repeat.
  Future<Result<bool>> challenged(DuelChallenge challenge) async {
    if (challenge.targetUserId == null) {
      return const Result.ok(false);
    }
    final found = await _notices.challengedNotice(challenge.id);
    if (found is Err<DuelNotice?>) return Result.err(found.error);
    final notice = (found as Ok<DuelNotice?>).value;
    if (notice == null) return const Result.ok(false);
    return _deliver(
      notice: notice,
      kind: NotificationKind.duelChallenged,
      subject: NotificationSubject.duelChallenged(
        challengeId: challenge.id,
        actorUserId: notice.actorUserId,
      ),
      title: challengedTitle,
      body:
          '${notice.actorName} يتحداك في ${notice.homeTeam} × '
          '${notice.awayTeam}. اضغط وتوقّع.',
      link: PushLink.duelChallenge(notice.code),
    );
  }

  /// Tells the challenger behind [duel] that it was accepted.
  Future<Result<bool>> accepted(Duel duel) async {
    final found = await _notices.acceptedNotice(duel.id);
    if (found is Err<DuelNotice?>) return Result.err(found.error);
    final notice = (found as Ok<DuelNotice?>).value;
    if (notice == null) return const Result.ok(false);
    return _deliver(
      notice: notice,
      kind: NotificationKind.duelAccepted,
      subject: NotificationSubject.duelAccepted(
        challengeId: duel.challengeId,
        actorUserId: notice.actorUserId,
      ),
      title: acceptedTitle,
      body:
          '${notice.actorName} قبل تحديك في ${notice.homeTeam} × '
          '${notice.awayTeam}.',
      link: PushLink.duel,
    );
  }

  Future<Result<bool>> _deliver({
    required DuelNotice notice,
    required NotificationKind kind,
    required NotificationSubject subject,
    required String title,
    required String body,
    required String link,
  }) async {
    final created = await _create(
      recipientId: notice.recipientUserId,
      kind: kind,
      subject: subject,
    );
    if (created is Err<bool>) return Result.err(created.error);
    // Already told: a retry must not ring the same phone again.
    if (!(created as Ok<bool>).value) return const Result.ok(false);
    if (notice.tokens.isEmpty) return const Result.ok(true);

    final DateTime now = _clock.nowUtc();
    if (QuietHours.covers(now, utcOffsetMinutes: notice.utcOffsetMinutes)) {
      final queued = await _queue.enqueue(<PushToQueue>[
        PushToQueue(
          id: _idGenerator.newUuid(),
          userId: notice.recipientUserId,
          title: title,
          body: body,
          deliverAfter: QuietHours.endsAt(
            now,
            utcOffsetMinutes: notice.utcOffsetMinutes,
          ),
        ),
      ]);
      return switch (queued) {
        Ok<void>() => const Result.ok(true),
        Err<void>(:final error) => Result.err(error),
      };
    }

    final sent = await _sender.send(
      tokens: notice.tokens,
      title: title,
      body: body,
      link: link,
    );
    return switch (sent) {
      Ok<List<String>>() => const Result.ok(true),
      Err<List<String>>(:final error) => Result.err(error),
    };
  }
}
