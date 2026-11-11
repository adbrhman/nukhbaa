import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:application/src/support/send_support_message.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One prediction of a match not yet started, as support reads it.
final class SupportPeekedPrediction {
  /// Creates the line.
  const SupportPeekedPrediction({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
    this.leagueName,
  });

  /// The match.
  final FixtureRef fixture;

  /// Its home side.
  final String homeTeam;

  /// Its away side.
  final String awayTeam;

  /// Its kickoff, UTC.
  final DateTime kickoffAt;

  /// The predicted home goals.
  final int homeGoals;

  /// The predicted away goals.
  final int awayGoals;

  /// Whether the player made it his day's double.
  final bool isDouble;

  /// Its league's name, when it has one.
  final String? leagueName;
}

/// What support read, and the message that told the player so.
final class SupportPredictionsPeek {
  /// Creates the reading.
  const SupportPredictionsPeek({
    required this.notice,
    required this.predictions,
  });

  /// The message stored in the player's conversation (the route pushes it
  /// to him as any support answer).
  final SupportMessageStored notice;

  /// The player's predictions of the matches not yet started, by kickoff.
  final List<SupportPeekedPrediction> predictions;
}

/// The one reading of a prediction before its kickoff, by anyone
/// (decided by the owner on 2026-11-11, script 261): the admins play like
/// any player, so neither the match's predictions nor a player's history
/// show a match that has not started. From a player's own support
/// conversation an admin may read that player's predictions of the matches
/// not yet started, to answer him (a prediction he says was not saved, a
/// double he says moved).
///
/// It is never silent:
/// * the player must have written to support: one of his messages is among
///   the conversation's last [recentMessages] (an admin who wrote first
///   cannot read anything before the player answers);
/// * a reason is required ([reasonMaxLength] characters at most);
/// * the reading is kept in the audit trail (`support_predictions_viewed`,
///   the player as target, the reason as typed);
/// * the player is told in the same conversation ([noticeText]), as a
///   support answer that reaches his phone.
///
/// The predictions are read first and returned last: a failed audit or a
/// failed notice returns its error and shows nothing. Admin only. Never
/// throws; returns a typed [Result].
final class SupportPeekPredictions {
  /// Creates the use-case over its collaborators.
  const SupportPeekPredictions({
    required SupportChatRepository chats,
    required AdminReplySupport reply,
    required FixturePredictionRepository predictions,
    required FixtureScheduleRepository schedules,
    required AuditRecorder audit,
    required Clock clock,
  }) : _chats = chats,
       _reply = reply,
       _predictions = predictions,
       _schedules = schedules,
       _audit = audit,
       _clock = clock;

  final SupportChatRepository _chats;
  final AdminReplySupport _reply;
  final FixturePredictionRepository _predictions;
  final FixtureScheduleRepository _schedules;
  final AuditRecorder _audit;
  final Clock _clock;

  /// The longest reason kept.
  static const int reasonMaxLength = 200;

  /// How far back a message of the player's is looked for.
  static const int recentMessages = 50;

  /// What the player reads in his conversation.
  static const String noticeText =
      'اطّلع فريق الدعم على توقعاتك للمباريات التي لم تبدأ بعد، لمتابعة '
      'طلبك في هذه المحادثة. لا يطّلع أحد على توقعاتك قبل انطلاق المباراة '
      'إلا هكذا، ويُسجَّل كل اطلاع.';

  /// A blank or too long reason.
  static const AppError reasonInvalid = AppError.validation(
    'support.peek_reason_invalid',
    'اكتب سبب الاطلاع (200 حرف على الأكثر).',
  );

  /// The player has not written in the conversation.
  static const AppError needsPlayerMessage = AppError.invariant(
    'support.peek_needs_player_message',
    'يُتاح الاطلاع بعد أن يراسل اللاعب الدعم في هذه المحادثة.',
  );

  /// Reads the open predictions of [conversationId]'s player for
  /// [principal], who must be an admin, for [reason].
  Future<Result<SupportPredictionsPeek>> call({
    required AuthenticatedUser principal,
    required String conversationId,
    required String? reason,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final id = SupportConversationId.tryParse(conversationId);
    if (id is Err<SupportConversationId>) return Result.err(id.error);
    final why = (reason ?? '').trim();
    if (why.isEmpty || why.length > reasonMaxLength) {
      return const Result.err(reasonInvalid);
    }

    final conversation = (id as Ok<SupportConversationId>).value;
    final summary = await _chats.conversation(conversation);
    if (summary is Err<SupportConversationSummary>) {
      return Result.err(summary.error);
    }
    final player = (summary as Ok<SupportConversationSummary>).value.playerId;

    final thread = await _chats.conversationThread(
      conversationId: conversation,
      beforeId: null,
      limit: recentMessages,
    );
    if (thread is Err<SupportThread>) return Result.err(thread.error);
    final wrote = (thread as Ok<SupportThread>).value.messages.any(
      (message) => message.senderRole == SupportSenderRole.player,
    );
    if (!wrote) return const Result.err(needsPlayerMessage);

    final open = await _openPredictions(player);
    if (open is Err<List<SupportPeekedPrediction>>) {
      return Result.err(open.error);
    }

    final audited = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.supportPredictionsViewed,
      targetRef: player.value,
      reason: why,
    );
    if (audited is Err<AuditEntry>) return Result.err(audited.error);

    final notice = await _reply(
      principal: principal,
      conversationId: conversation.value,
      text: noticeText,
    );
    if (notice is Err<SupportMessageStored>) return Result.err(notice.error);

    return Result.ok(
      SupportPredictionsPeek(
        notice: (notice as Ok<SupportMessageStored>).value,
        predictions: (open as Ok<List<SupportPeekedPrediction>>).value,
      ),
    );
  }

  Future<Result<List<SupportPeekedPrediction>>> _openPredictions(
    UserId player,
  ) async {
    final listed = await _predictions.listByUser(player);
    if (listed is Err<List<FixturePredictionView>>) {
      return Result.err(listed.error);
    }
    final views = (listed as Ok<List<FixturePredictionView>>).value;
    if (views.isEmpty) return const Result.ok(<SupportPeekedPrediction>[]);
    final found = await _schedules.findByFixtures(
      <FixtureRef>{
        for (final view in views) view.prediction.fixture,
      }.toList(growable: false),
    );
    if (found is Err<List<FixtureSchedule>>) return Result.err(found.error);
    final byFixture = <String, FixtureSchedule>{
      for (final schedule in (found as Ok<List<FixtureSchedule>>).value)
        schedule.fixture.value: schedule,
    };
    final now = _clock.nowUtc();
    final lines =
        <SupportPeekedPrediction>[
          for (final view in views)
            if (byFixture[view.prediction.fixture.value] case final schedule?)
              if (now.isBefore(schedule.kickoffAt.toUtc()))
                SupportPeekedPrediction(
                  fixture: view.prediction.fixture,
                  homeTeam: schedule.homeTeam,
                  awayTeam: schedule.awayTeam,
                  kickoffAt: schedule.kickoffAt.toUtc(),
                  homeGoals: view.prediction.homeGoals,
                  awayGoals: view.prediction.awayGoals,
                  isDouble: view.prediction.isDouble,
                  leagueName: schedule.leagueName,
                ),
        ]..sort((a, b) {
          final byKickoff = a.kickoffAt.compareTo(b.kickoffAt);
          return byKickoff != 0
              ? byKickoff
              : a.fixture.value.compareTo(b.fixture.value);
        });
    return Result.ok(lines);
  }
}
